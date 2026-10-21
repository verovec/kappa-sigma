internal import Foundation
package import Metal

/// Two-scale HDR core compression on linear data: galaxy cores keep their structure instead of
/// rendering flat white once stretched.
///
/// Card 0052, the port of the v9 runbook's hdrcomp. The luminance (mean of the planes) is split
/// into a smooth part — a grey opening first, so stars never enter it (else dark rings, PO
/// 2026-10-18), then three box passes approximating a Gaussian of σ — and the detail. Above
/// t1 = sky + `kneeAboveSky` the smooth part alone is asinh-compressed with softness `softness`
/// (slope 1 at t1: monotone and C1, no knee ring); the detail is put back and every plane is
/// scaled by the one ratio L′/L, so colour is kept.
///
/// R2: the thresholds are absolute above the bundle's sky (the mean of its plane medians), never
/// multiples of a sky the process measures; values applied = values shown.
package struct HDRProcess: ImageProcess {
  package static let id = "hdr"
  package static let title = "HDR core compression"
  package static let stage = ProcessStage.linear
  package static let previewExactOnlyAt1to1 = true

  /// The PO's final choice on M 31 (2026-10-19): knee 0.00084 above the sky, softness 0.00118.
  package static let schema = ParamSchema([
    ParamSpec(id: "enabled", title: "Compress the core", level: .simple, flag: false),
    ParamSpec(
      id: "kneeAboveSky", title: "Knee above the sky", unit: .none, level: .simple,
      number: 0.000_84, in: 0...0.1),
    ParamSpec(
      id: "softness", title: "Softness", unit: .none, level: .simple, number: 0.001_18,
      in: 0.000_01...0.1),
    ParamSpec(
      id: "sigma", title: "Smooth scale σ", unit: .px, level: .advanced, number: 30, in: 0...200),
    ParamSpec(
      id: "openRadius", title: "Star removal radius", unit: .px, level: .advanced, number: 16,
      in: 0...64),
  ])

  package let params: ParamSet
  private let luminance: MTLComputePipelineState
  private let compress: MTLComputePipelineState
  private let blur: BoxBlur
  private let morphology: GreyMorphology

  package init(params: ParamSet, device: MTLDevice) throws {
    self.params = params
    let library = try ProcessLibrary.library(device: device, file: "HDR.metal")
    luminance = try ProcessLibrary.pipeline(library: library, function: "hdrLuminance")
    compress = try ProcessLibrary.pipeline(library: library, function: "hdrCompress")
    blur = try BoxBlur(device: device)
    morphology = try GreyMorphology(device: device)
  }

  package func render(
    _ input: GPUImage, stats: LayerStats, into output: GPUImage, context: RenderContext
  ) throws {
    let channels = input.planes.count
    guard channels == 1 || channels == 3, output.planes.count == channels,
      output.width == input.width, output.height == input.height
    else { throw ProcessError.sizeMismatch }
    guard params.flag("enabled") else { return try Self.copy(input, into: output, context) }
    guard stats.channels.count >= channels else {
      throw ProcessError.invalidParameter("HDR needs the bundle sky: the statistics of each plane")
    }
    let sky = stats.channels.prefix(channels).map(\.median).reduce(0, +) / Double(channels)
    let values = [
      Float(channels), Float(sky + params.number("kneeAboveSky")), Float(params.number("softness")),
    ]
    let device = context.commands.device
    let colour = (0..<3).map { input.planes[min($0, channels - 1)] }
    let lum = try ScratchTexture.make(like: input.planes[0], device: device)
    try encode(luminance, textures: colour + [lum], values: values, context)

    var smooth = lum
    // Rounded like hdrcomp's integer radius: under half a working pixel there is no opening.
    let radius = Int((params.number("openRadius") / context.scale).rounded())
    if radius > 0 {
      smooth = try ScratchTexture.make(like: lum, device: device)
      try morphology.encodeOpening(lum, into: smooth, radius: radius, commands: context.commands)
    }
    let radii = Self.boxRadii(sigma: params.number("sigma") / context.scale)
    if !radii.isEmpty {
      let blurred = try ScratchTexture.make(like: lum, device: device)
      try blur.encode(smooth, into: blurred, radii: radii, commands: context.commands)
      smooth = blurred
    }
    let outputs = (0..<3).map { output.planes[min($0, channels - 1)] }
    try encode(compress, textures: colour + [lum, smooth] + outputs, values: values, context)
  }

  /// The radii of hdrcomp's three box passes for a Gaussian of `sigma` working pixels (Kovesi's
  /// odd widths: the largest odd width under the ideal one, then the next), passes of radius 0
  /// dropped; none when `sigma` is 0.
  static func boxRadii(sigma: Double) -> [Int] {
    guard sigma > 0 else { return [] }
    var lower = Int((4 * sigma * sigma + 1).squareRoot().rounded(.down))
    if lower % 2 == 0 { lower -= 1 }
    let atLower =
      (12 * sigma * sigma - Double(3 * lower * lower + 12 * lower + 9))
      / Double(-4 * lower - 4)
    return (0..<3).map { ($0 < Int(atLower.rounded()) ? lower : lower + 2) / 2 }.filter { $0 > 0 }
  }

  /// One pass of `pipeline` over its last texture: `textures` bound in order, `values` at 0.
  private func encode(
    _ pipeline: MTLComputePipelineState, textures: [MTLTexture], values: [Float],
    _ context: RenderContext
  ) throws {
    guard let encoder = context.commands.makeComputeCommandEncoder(), let target = textures.last
    else { throw ProcessError.commandFailed("HDR encoder") }
    var values = values
    encoder.setComputePipelineState(pipeline)
    for (index, texture) in textures.enumerated() { encoder.setTexture(texture, index: index) }
    unsafe encoder.setBytes(&values, length: values.count * MemoryLayout<Float>.stride, index: 0)
    encoder.dispatchThreads(
      MTLSize(width: target.width, height: target.height, depth: 1),
      threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
    encoder.endEncoding()
  }

  /// Off: the input, bit for bit.
  private static func copy(_ input: GPUImage, into output: GPUImage, _ context: RenderContext)
    throws
  {
    guard let blit = context.commands.makeBlitCommandEncoder() else {
      throw ProcessError.commandFailed("HDR copy encoder")
    }
    for (source, target) in zip(input.planes, output.planes) { blit.copy(from: source, to: target) }
    blit.endEncoding()
  }
}
