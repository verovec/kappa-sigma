internal import Foundation
internal import ImageKit
package import Metal

/// Removes noise on linear data with the starlet (à-trous B3) transform: each of the four finest
/// scales is soft-thresholded at its own strength, the coarse residual is kept (card 0115).
///
/// A strength k at scale j thresholds at k · σⱼ · `noise`, σⱼ the white-noise sigma of the scale
/// (`StarletNoise`) and `noise` the image's noise σ, a value the panel shows (R2: the process
/// never measures it; the app offers the measured one). The luminance and the colour of the
/// result are put back at their own amounts; `protectStars` keeps what stands 5 to 10 `noise`
/// above the plane's median (`StarletNoise.protection`, StackKit's band). Amount 0 (the
/// default), noise 0, every strength 0 or nothing kept of the result (`blendWeights` both 0: the
/// luminance amount alone on a mono plane) returns the input bit for bit.
package struct DenoiseProcess: ImageProcess {
  package static let id = "denoise"
  package static let title = "Denoise"
  package static let stage = ProcessStage.linear
  // A starlet scale is a distance in pixels: the half-size preview is not the same transform.
  package static let previewExactOnlyAt1to1 = true
  /// The strengths of scales 1…4 (1, 2, 4 and 8 px): StackKit's deep-sky preset.
  package static let presetStrengths = [3.0, 2.5, 1.8, 1.0]

  package static let schema = ParamSchema(
    [
      ParamSpec(
        id: "amount", title: "Amount", unit: .opacity, level: .simple, number: 0, in: 0...1),
      ParamSpec(
        id: "noise", title: "Noise level", unit: .none, level: .simple, number: 0, in: 0...1),
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
    "the noise measured on the image's finest starlet scale (median of its planes)"
  ]

  /// Finer arrows for the noise level: a deep-sky σ is a few thousandths.
  package static let steps = ["noise": 0.0001]

  /// The noise level `measured` (σ in image units, one per plane), offered, never applied (R2).
  ///
  /// The median of the planes, to four significant digits; none when nothing was measured.
  package static func suggestions(measured: [Double]) -> [Suggestion] {
    let values = measured.filter { $0 > 0 && $0.isFinite }.sorted()
    guard !values.isEmpty else { return [] }
    let middle = values.count / 2
    let median =
      values.count % 2 == 1 ? values[middle] : (values[middle - 1] + values[middle]) / 2
    let digits = pow(10, 3 - floor(log10(median)))
    let noise = min((median * digits).rounded() / digits, 1)
    return [Suggestion(paramID: "noise", value: .number(noise), reason: suggestionReasons[0])]
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
    guard [1, 3].contains(input.planes.count), output.planes.count == input.planes.count,
      output.width == input.width, output.height == input.height
    else { throw ProcessError.sizeMismatch }
    // Nothing to threshold or nothing kept of the result is the input bit for bit, not a
    // recomposition rounded in float.
    let thresholds = (1...4).contains { params.number("scale\($0)") > 0 }
    let weights = blendWeights(planes: input.planes.count)
    let kept = weights.luminance > 0 || weights.colour > 0
    guard params.number("noise") > 0, thresholds, kept else {
      return try copy(input, into: output, commands: context.commands)
    }
    let protects = params.flag("protectStars")
    guard !protects || !stats.channels.isEmpty else {
      throw ProcessError.invalidParameter("protecting the stars needs the image's median")
    }
    let device = context.commands.device
    // The mask is only read when the stars are protected.
    let scratch = try (0..<(protects ? 4 : 3)).map { _ in
      try ScratchTexture.make(like: input.planes[0], device: device)
    }
    for (channel, plane) in input.planes.enumerated() {
      let median =
        stats.channels.isEmpty ? 0 : stats.channels[min(channel, stats.channels.count - 1)].median
      try denoise(
        plane, into: output.planes[channel], median: median, scratch: scratch,
        commands: context.commands)
    }
    try encodeBlend(input, into: output, commands: context.commands)
  }

  /// The denoised `plane` into `target`: c₀ → c₁ → c₂ (the protection's smooth) → c₃ → c₄, each
  /// detail cⱼ − cⱼ₊₁ thresholded into `target`, then c₄ added back.
  private func denoise(
    _ plane: MTLTexture, into target: MTLTexture, median: Double, scratch: [MTLTexture],
    commands: MTLCommandBuffer
  ) throws {
    let (fine, coarse, row) = (scratch[0], scratch[1], scratch[2])
    // Unread without protection: any texture fills the kernel's slot.
    let mask = scratch.count > 3 ? scratch[3] : row
    let protects = params.flag("protectStars")
    let sigma = params.number("noise")
    try smooth(plane, into: fine, step: 1, row: row, commands: commands)
    try smooth(fine, into: coarse, step: 2, row: row, commands: commands)
    if protects {
      try encodeProtection(coarse, into: mask, median: median, sigma: sigma, commands: commands)
    }
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
