internal import ImageKit
package import Metal

/// Removes noise on linear data with the starlet (à-trous B3) transform: each of the four finest
/// scales is soft-thresholded at its own strength, the coarse residual is kept (card 0115).
///
/// A strength k at scale j thresholds at k · σⱼ · σ, σⱼ the white-noise sigma of the scale
/// (`StarletNoise`) and σ the plane's MADN from the stats the step receives (R2: never measured
/// by the process). The luminance and the colour of the result are put back at their own
/// amounts; `protectStars` keeps what stands 5 to 10 σ above the median (StackKit's
/// `StarletDenoiser` band). Amount 0, the default, returns the input bit for bit.
package struct DenoiseProcess: ImageProcess {
  package static let id = "denoise"
  package static let title = "Denoise"
  package static let stage = ProcessStage.linear
  // A starlet scale is a distance in pixels: the half-size preview is not the same transform.
  package static let previewExactOnlyAt1to1 = true
  /// The strengths of scales 1…4 (1, 2, 4 and 8 px): StackKit's deep-sky preset.
  package static let presetStrengths = [3.0, 2.5, 1.8, 1.0]
  /// The SNR band (σ above the median) over which a protected pixel goes from denoised to kept.
  static let protection: (low: Float, high: Float) = (5, 10)

  package static let schema = ParamSchema(
    [
      ParamSpec(
        id: "amount", title: "Amount", unit: .opacity, level: .simple, number: 0, in: 0...1)
    ]
      + presetStrengths.enumerated().map { scale, strength in
        ParamSpec(
          id: "scale\(scale + 1)", title: "Scale \(scale + 1) strength", unit: .sigma,
          level: .simple, number: strength, in: 0...10)
      } + [
        ParamSpec(id: "protectStars", title: "Protect stars", level: .simple, flag: false),
        ParamSpec(
          id: "luminance", title: "Luminance amount", unit: .opacity, level: .advanced, number: 1,
          in: 0...1),
        ParamSpec(
          id: "chrominance", title: "Colour amount", unit: .opacity, level: .advanced, number: 1,
          in: 0...1),
      ])

  /// The reasons the panel shows next to a suggestion: English keys of the catalog.
  package static let suggestionReasons = [
    "3 σ of the noise measured on the finest scale (the image's MADN also counts its signal)"
  ]

  /// The scale-1 strength that thresholds at 3 σ of `noise`, offered, never applied (R2).
  ///
  /// `noise` is the image noise measured on its finest starlet scale; the threshold's σ is the
  /// head's MADN (`stats`). None without both.
  package static func suggestions(noise: Double, stats: LayerStats) -> [Suggestion] {
    guard let madn = stats.channels.first?.madn, madn > 0, noise > 0, noise.isFinite else {
      return []
    }
    let strength = min(max((3 * noise / madn * 100).rounded() / 100, 0), 10)
    return [
      Suggestion(paramID: "scale1", value: .number(strength), reason: suggestionReasons[0])
    ]
  }

  package let params: ParamSet
  let pass: MTLComputePipelineState
  let protect: MTLComputePipelineState
  let detail: MTLComputePipelineState
  let recompose: MTLComputePipelineState
  let blend: MTLComputePipelineState

  package init(params: ParamSet, device: MTLDevice) throws {
    self.params = params
    let library = try ProcessLibrary.library(device: device, file: "Denoise.metal")
    pass = try ProcessLibrary.pipeline(library: library, function: "starletPass")
    protect = try ProcessLibrary.pipeline(library: library, function: "denoiseProtection")
    detail = try ProcessLibrary.pipeline(library: library, function: "denoiseDetail")
    recompose = try ProcessLibrary.pipeline(library: library, function: "denoiseRecompose")
    blend = try ProcessLibrary.pipeline(library: library, function: "denoiseBlend")
  }

  package func render(
    _ input: GPUImage, stats: LayerStats, into output: GPUImage, context: RenderContext
  ) throws {
    guard output.planes.count == input.planes.count, output.width == input.width,
      output.height == input.height
    else { throw ProcessError.sizeMismatch }
    let amount = params.number("amount")
    guard amount > 0 else { return try copy(input, into: output, commands: context.commands) }
    guard !stats.channels.isEmpty else {
      throw ProcessError.invalidParameter("denoise needs the image's noise statistics")
    }
    let device = context.commands.device
    let scratch = try (0..<4).map { _ in
      try ScratchTexture.make(like: input.planes[0], device: device)
    }
    for (channel, plane) in input.planes.enumerated() {
      let noise = stats.channels[min(channel, stats.channels.count - 1)]
      try denoise(
        plane, into: output.planes[channel], noise: noise, scratch: scratch,
        commands: context.commands)
    }
    try encodeBlend(input, into: output, amount: amount, commands: context.commands)
  }

  /// The denoised `plane` into `target`: c₀ → c₁ → c₂ (the protection's smooth) → c₃ → c₄, each
  /// detail cⱼ − cⱼ₊₁ thresholded into `target`, then c₄ added back.
  private func denoise(
    _ plane: MTLTexture, into target: MTLTexture, noise: ChannelStats, scratch: [MTLTexture],
    commands: MTLCommandBuffer
  ) throws {
    let (fine, coarse, row, mask) = (scratch[0], scratch[1], scratch[2], scratch[3])
    let protects = params.flag("protectStars")
    try smooth(plane, into: fine, step: 1, row: row, commands: commands)
    try smooth(fine, into: coarse, step: 2, row: row, commands: commands)
    if protects { try encodeProtection(coarse, into: mask, noise: noise, commands: commands) }
    let sigma = noise.madn
    let levels = [(plane, fine), (fine, coarse), (coarse, fine), (fine, coarse)]
    for (scale, (from, to)) in levels.enumerated() {
      if scale == 2 { try smooth(coarse, into: fine, step: 4, row: row, commands: commands) }
      if scale == 3 { try smooth(fine, into: coarse, step: 8, row: row, commands: commands) }
      let threshold = params.number("scale\(scale + 1)") * StarletNoise.scaleSigma(scale) * sigma
      var values = [Float(threshold), scale == 0 ? 1 : 0, protects ? 1 : 0]
      try dispatch(detail, [from, to, mask, target], &values, size: target, commands: commands)
    }
    var none: [Float] = []
    try dispatch(recompose, [coarse, target], &none, size: target, commands: commands)
  }
}
