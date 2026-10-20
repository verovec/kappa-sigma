package import Metal

/// The first non-linear step: MTF (HistogramTransformation / Siril autostretch), GHS or asinh,
/// with an optional highlight headroom cap before it.
///
/// Design §2 and card 0050. MTF places the shadows `shadowsClip` σ from the bundle median and
/// sends the median to `targetBackground` (Siril `autostretch`); GHS follows the Generalised
/// Hyperbolic Stretch equations (Siril `ght`); asinh is ratio-preserving. The headroom cap is the
/// legacy `applyStretchHeadroom` shoulder: linear cores roll off below `headroom` with their
/// colour ratios kept.
///
/// R2: the shadows and midtone come from the bundle statistics and the values the panel shows;
/// "autostretch like Siril" is a suggestion, never a hidden mode.
package struct StretchProcess: ImageProcess {
  package static let id = "stretch"
  package static let title = "Stretch"
  package static let stage = ProcessStage.linear
  package static let previewExactOnlyAt1to1 = false
  /// The modes, in panel order.
  package static let modes = ["mtf", "ghs", "asinh"]

  package static let schema = ParamSchema([
    ParamSpec(id: "mode", title: "Mode", level: .simple, choice: "mtf", of: modes),
    ParamSpec(
      id: "shadowsClip", title: "Shadows clip", unit: .sigma, level: .simple, number: -2.8,
      in: -10...0),
    ParamSpec(
      id: "targetBackground", title: "Target background", unit: .none, level: .simple,
      number: 0.25, in: 0.01...0.6),
    ParamSpec(id: "linked", title: "Linked channels", level: .simple, flag: true),
    ParamSpec(
      id: "ghsStretch", title: "Stretch factor ln(D+1)", unit: .none, level: .simple, number: 0,
      in: 0...10),
    ParamSpec(
      id: "ghsIntensity", title: "Local intensity b", unit: .none, level: .simple, number: 0,
      in: -5...15),
    ParamSpec(
      id: "ghsSymmetry", title: "Symmetry point", unit: .none, level: .simple, number: 0,
      in: 0...1),
    ParamSpec(
      id: "ghsShadows", title: "Shadow protection", unit: .none, level: .advanced, number: 0,
      in: 0...1),
    ParamSpec(
      id: "ghsHighlights", title: "Highlight protection", unit: .none, level: .advanced,
      number: 1, in: 0...1),
    ParamSpec(
      id: "asinhStretch", title: "Stretch factor β", unit: .none, level: .simple, number: 0,
      in: 0...1000),
    ParamSpec(
      id: "asinhBlack", title: "Black point", unit: .none, level: .simple, number: 0, in: 0...0.5),
    ParamSpec(
      id: "headroom", title: "Highlight headroom", unit: .none, level: .advanced, number: 1,
      in: 0.5...1),
  ])

  package let params: ParamSet
  private let pipeline: MTLComputePipelineState

  package init(params: ParamSet, device: MTLDevice) throws {
    self.params = params
    pipeline = try ProcessLibrary.pipeline(device: device, file: "Stretch.metal", function: "stretch")
  }

  package func render(
    _ input: GPUImage, stats: LayerStats, into output: GPUImage, context: RenderContext
  ) throws {
    let channels = input.planes.count
    guard channels == 1 || channels == 3, output.planes.count == channels,
      output.width == input.width, output.height == input.height
    else { throw ProcessError.sizeMismatch }
    var values = try StretchUniforms(params: params, channels: channels, stats: stats).values
    guard let encoder = context.commands.makeComputeCommandEncoder() else {
      throw ProcessError.commandFailed("stretch encoder")
    }
    encoder.setComputePipelineState(pipeline)
    for slot in 0..<3 {
      encoder.setTexture(input.planes[min(slot, channels - 1)], index: slot)
      encoder.setTexture(output.planes[min(slot, channels - 1)], index: 3 + slot)
    }
    unsafe encoder.setBytes(&values, length: values.count * MemoryLayout<Float>.stride, index: 0)
    encoder.dispatchThreads(
      MTLSize(width: output.width, height: output.height, depth: 1),
      threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
    encoder.endEncoding()
  }
}
