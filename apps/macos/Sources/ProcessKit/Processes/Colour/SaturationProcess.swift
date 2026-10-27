package import Metal

/// Saturation on stretched data: an HSL saturation boost through a luminosity band-pass, a
/// star-core desaturation and a global luma desaturation.
///
/// Card 0053, ports of the PO's tools: astrocomp's `-sat -sat-masked` (the band of
/// `gimp.saturationMaskLUT(0.12, 0.45, 0.70, 0.30)` on the HSL lightness: the sky's chroma noise
/// is protected, star cores get a fraction), the compose step's star-core desaturation
/// (`starDesatMaskLUT(0.50, 0.85)` on the luminance of a greyscale mask copy, a desaturated copy
/// blended through it — in HSL, the same as scaling S by 1 − desat·mask) and the `desat` tool (Rec. 709 luma, `k = 1` untouched,
/// IC 1848 "doux" 0.62). Defaults change nothing.
package struct SaturationProcess: ImageProcess {
  package static let id = "saturation"
  package static let title = "Saturation"
  package static let stage = ProcessStage.nonlinear
  package static let previewExactOnlyAt1to1 = false

  package static let schema = ParamSchema([
    ParamSpec(
      id: "amount", title: "Saturation boost", unit: .none, level: .simple, number: 0, in: 0...2),
    ParamSpec(id: "masked", title: "Protect sky and highlights", level: .simple, flag: true),
    ParamSpec(
      id: "bandLow", title: "Band start", unit: .none, level: .advanced, number: 0.12, in: 0...1),
    ParamSpec(
      id: "bandHigh", title: "Band full", unit: .none, level: .advanced, number: 0.45, in: 0...1),
    ParamSpec(
      id: "rolloffStart", title: "Highlight roll-off", unit: .none, level: .advanced,
      number: 0.70, in: 0...0.99),
    ParamSpec(
      id: "highlightFloor", title: "Boost left at white", unit: .opacity, level: .advanced,
      number: 0.30, in: 0...1),
    ParamSpec(
      id: "starDesat", title: "Star-core desaturation", unit: .opacity, level: .simple, number: 0,
      in: 0...1),
    ParamSpec(
      id: "starDesatLow", title: "Star-core start", unit: .none, level: .advanced, number: 0.50,
      in: 0...1),
    ParamSpec(
      id: "starDesatHigh", title: "Star-core full", unit: .none, level: .advanced, number: 0.85,
      in: 0...1),
    ParamSpec(
      id: "lumaDesat", title: "Colour kept", unit: .opacity, level: .simple, number: 1, in: 0...1),
  ])

  package let params: ParamSet
  private let pipeline: MTLComputePipelineState

  package init(params: ParamSet, device: MTLDevice) throws {
    self.params = params
    pipeline = try ColourKernel.pipeline(device: device, function: "saturation")
  }

  /// The reasons the panel shows next to a suggestion: English keys of the catalog.
  package static let suggestionReasons = [
    "a moderate boost of 0.32",
    "the boost skips the sky's chroma noise and tames star cores",
    "a soft finish: colour kept at 0.62",
  ]

  /// Two finishes worth offering (a 0.32 boost, a soft finish keeping 62 % of the colour); none applied.
  package func suggestions(stats: LayerStats) -> [Suggestion] {
    let reasons = Self.suggestionReasons
    return [
      Suggestion(paramID: "amount", value: .number(0.32), reason: reasons[0]),
      Suggestion(paramID: "masked", value: .flag(true), reason: reasons[1]),
      Suggestion(paramID: "lumaDesat", value: .number(0.62), reason: reasons[2]),
    ]
  }

  /// The kernel's `p[]` (see Colour.metal); a band whose edges cross is refused when it is
  /// read (its boost or desaturation above 0).
  func uniforms() throws -> [Float] {
    let band = ["bandLow", "bandHigh", "rolloffStart"].map { params.number($0) }
    let boosted = params.number("amount") > 0 && params.flag("masked")
    guard !boosted || (band[0] < band[1] && band[1] <= band[2]) else {
      throw ProcessError.invalidParameter(
        "the saturation band needs start < full ≤ highlight roll-off")
    }
    let (starLow, starHigh) = (params.number("starDesatLow"), params.number("starDesatHigh"))
    guard params.number("starDesat") == 0 || starLow < starHigh else {
      throw ProcessError.invalidParameter("the star-core band needs start < full")
    }
    return [
      params.number("amount"), params.flag("masked") ? 1 : 0, band[0], band[1], band[2],
      params.number("highlightFloor"), params.number("starDesat"), starLow, starHigh,
      params.number("lumaDesat"),
    ].map { Float($0) }
  }

  package func render(
    _ input: GPUImage, stats: LayerStats, into output: GPUImage, context: RenderContext
  ) throws {
    try ColourKernel.checkSizes(input, output)
    // Saturation has no meaning on one plane: the mono image goes through untouched.
    guard input.planes.count == 3 else {
      return try ColourKernel.copy(input, into: output, commands: context.commands)
    }
    let values = try uniforms()
    try ColourKernel.encode(
      pipeline, input, into: output, values: values, commands: context.commands)
  }
}
