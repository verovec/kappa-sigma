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
    pipeline = try ProcessLibrary.pipeline(
      device: device, file: "Stretch.metal", function: "stretch")
  }

  /// The reasons the panel shows next to a suggestion: English keys of the catalog.
  package static let suggestionReasons = [
    "autostretch like Siril: shadows 2.8σ below the background",
    "autostretch like Siril: background at 0.25",
    "autostretch like Siril: one curve for every channel keeps the colour balance",
    "the deep-sky preset caps linear cores at 0.90 so star colours survive the stretch",
    "GHS symmetry point on the background median: the stretch opens the faint signal",
  ]

  /// Siril's autostretch (−2.8σ, background 0.25, linked), the deep-sky preset's 0.90 headroom,
  /// and the GHS symmetry point on the layer's mean median, kept between the current protection
  /// points; none is applied by itself.
  package func suggestions(stats: LayerStats) -> [Suggestion] {
    let reasons = Self.suggestionReasons
    var suggestions = [
      Suggestion(paramID: "shadowsClip", value: .number(-2.8), reason: reasons[0]),
      Suggestion(paramID: "targetBackground", value: .number(0.25), reason: reasons[1]),
      Suggestion(paramID: "linked", value: .flag(true), reason: reasons[2]),
      Suggestion(paramID: "headroom", value: .number(0.9), reason: reasons[3]),
    ]
    // LayerStats holds one entry per plane of the layer: the mean is this layer's background.
    if !stats.channels.isEmpty {
      let median = stats.channels.map(\.median).reduce(0, +) / Double(stats.channels.count)
      let (low, high) = (params.number("ghsShadows"), params.number("ghsHighlights"))
      suggestions.append(
        Suggestion(
          paramID: "ghsSymmetry", value: .number(min(max(median, low), high)), reason: reasons[4]))
    }
    return suggestions
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
