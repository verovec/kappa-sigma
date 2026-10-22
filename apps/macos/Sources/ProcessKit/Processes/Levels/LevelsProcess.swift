package import Metal
package import RenderKit

/// Histogram transformation (PixInsight HistogramTransformation, Siril `mtf low mid high`): a
/// black point, a midtone balance and a white point, then an output range.
///
/// Card 0089. Each value goes through `stf` of the shared `STF.h` (the viewer's display
/// stretch, the same arithmetic): rescaled by the black and white points, clipped to [0, 1],
/// then through the midtones transfer function. Unlinked, each channel first takes its own
/// triple; the RGB/K triple always follows, then the output range maps [0, 1] onto
/// [`outputLow`, `outputHigh`]. Untouched, every value is the identity: the output is the input
/// bit for bit.
///
/// R2: the values come from the panel only; the display stretch and Siril's autostretch are
/// suggestions, shown before they are taken.
package struct LevelsProcess: ImageProcess {
  package static let id = "levels"
  package static let title = "Histogram transformation"
  package static let stage = ProcessStage.any
  package static let previewExactOnlyAt1to1 = false
  /// The triples, in panel order: RGB/K first, then each channel's own.
  package static let triples = ["rgb", "r", "g", "b"]

  package static let schema = ParamSchema(
    [ParamSpec(id: "linked", title: "Linked channels", level: .simple, flag: true)]
      + zip(triples, ["", "Red ", "Green ", "Blue "]).flatMap { triple, channel in
        let level: ParamLevel = triple == "rgb" ? .simple : .advanced
        return zip(
          ["Shadows", "Midtones", "Highlights"], [0, 0.5, 1] as [Double]
        ).map { value, fallback in
          ParamSpec(
            id: triple + value, title: channel.isEmpty ? value : channel + value.lowercased(),
            unit: .none, level: level, number: fallback, in: 0...1)
        }
      }
      + [
        ParamSpec(
          id: "outputLow", title: "Output low", unit: .none, level: .advanced, number: 0,
          in: 0...1),
        ParamSpec(
          id: "outputHigh", title: "Output high", unit: .none, level: .advanced, number: 1,
          in: 0...1),
      ])

  package let params: ParamSet
  private let pipeline: MTLComputePipelineState

  package init(params: ParamSet, device: MTLDevice) throws {
    self.params = params
    pipeline = try ProcessLibrary.pipeline(device: device, file: "Levels.metal", function: "levels")
  }

  /// The stretch of `triple` (`rgb`, `r`, `g` or `b`) in `params`.
  package static func stf(_ triple: String, of params: ParamSet) -> STFParameters {
    STFParameters(
      shadows: params.number(triple + "Shadows"), midtone: params.number(triple + "Midtones"),
      highlights: params.number(triple + "Highlights"))
  }

  /// `params` with `triple` set to `stf` (each value as the schema accepts it).
  package static func setting(_ stf: STFParameters, as triple: String, on params: ParamSet)
    throws -> ParamSet
  {
    var params = params
    try params.set(triple + "Shadows", .number(stf.shadows))
    try params.set(triple + "Midtones", .number(stf.midtone))
    try params.set(triple + "Highlights", .number(stf.highlights))
    return params
  }

  /// The per-channel triples are shown without the disclosure once the channels are unlinked.
  package static func promoted(_ params: ParamSet) -> Set<String> {
    guard !params.flag("linked") else { return [] }
    return Set(
      triples.dropFirst().flatMap { [$0 + "Shadows", $0 + "Midtones", $0 + "Highlights"] })
  }

  /// The reasons the panel shows next to a suggestion: English keys of the catalog.
  package static let suggestionReasons = [
    "autostretch like Siril: shadows 2.8σ below the background, background at 0.25",
    "the viewer's display stretch, made a real adjustment",
  ]

  /// Siril's autostretch on the head's statistics (linked: the mean of the channels), c1 = 1;
  /// none is applied by itself.
  package func suggestions(stats: LayerStats) -> [Suggestion] {
    guard !stats.channels.isEmpty else { return [] }
    let mapping = STFMapping.linked(
      stats.channels.map { STFMapping(median: $0.median, madn: $0.madn) })[0]
    let stf = mapping.parameters(
      sigma: AutoSTF.shadowsClip, targetBackground: AutoSTF.targetBackground)
    return Self.suggestions(stf, as: "rgb", reason: Self.suggestionReasons[0])
  }

  /// One suggestion per value of `stf` for `triple`, all with `reason` (taken together).
  package static func suggestions(_ stf: STFParameters, as triple: String, reason: String)
    -> [Suggestion]
  {
    [
      Suggestion(paramID: triple + "Shadows", value: .number(stf.shadows), reason: reason),
      Suggestion(paramID: triple + "Midtones", value: .number(stf.midtone), reason: reason),
      Suggestion(paramID: triple + "Highlights", value: .number(stf.highlights), reason: reason),
    ]
  }

  package func render(
    _ input: GPUImage, stats: LayerStats, into output: GPUImage, context: RenderContext
  ) throws {
    let channels = input.planes.count
    guard channels == 1 || channels == 3, output.planes.count == channels,
      output.width == input.width, output.height == input.height
    else { throw ProcessError.sizeMismatch }
    var values = try LevelsUniforms(params: params, channels: channels).values
    guard let encoder = context.commands.makeComputeCommandEncoder() else {
      throw ProcessError.commandFailed("levels encoder")
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
