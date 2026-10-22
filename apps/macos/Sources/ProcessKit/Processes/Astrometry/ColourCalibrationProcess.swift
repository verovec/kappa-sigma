package import Metal

/// Colour calibration (card 0094, design §3.2): Siril's SPCC or PCC on a plate-solved linear
/// image, the method and its spectral data chosen by the user — no ladder from one method to
/// another, no neutralisation fallback (R2; the manual route is `colour-balance`).
///
/// A host-tool process like plate solving (`hostTool`): the preview is the image itself, Apply
/// runs Siril through the tool the app injects, the step's output is Siril's pixels. It needs
/// the head's solution (`requiresSolution`). Unticked (`enabled` off — what the dual-band profile
/// ships, with its why: the filter's two lines have no broadband white), the step is the image
/// itself and runs no tool.
package struct ColourCalibrationProcess: ImageProcess {
  package static let id = "colour-calibration"
  package static let title = "Colour calibration"
  package static let stage = ProcessStage.linear
  package static let previewExactOnlyAt1to1 = false
  package static let hostTool = true
  package static let requiresSolution = true

  package static let schema = ParamSchema([
    ParamSpec(id: "enabled", title: "Calibrate the colours", level: .simple, flag: true),
    ParamSpec(id: "method", title: "Method", level: .simple, choice: "spcc", of: ["spcc", "pcc"]),
    ParamSpec(
      id: "sensor", title: "Sensor (SPCC)", level: .simple, choice: "Sony IMX571",
      of: SPCCNames.sensors),
    ParamSpec(
      id: "filter", title: "Filter on the camera (SPCC)", level: .simple, choice: "UV/IR Block",
      of: SPCCNames.filters),
    ParamSpec(
      id: "whiteReference", title: "White reference (SPCC)", level: .simple,
      choice: "Average Spiral Galaxy", of: SPCCNames.whiteReferences),
    ParamSpec(
      id: "limitMag", title: "Limit magnitude (0: automatic)", unit: .none, level: .advanced,
      number: 0, in: 0...22),
    ParamSpec(
      id: "bgTolBelow", title: "Background tolerance below (σ)", unit: .none, level: .advanced,
      number: 2.8, in: 0...10),
    ParamSpec(
      id: "bgTolAbove", title: "Background tolerance above (σ)", unit: .none, level: .advanced,
      number: 2, in: 0...10),
    ParamSpec(
      id: "catalogue", title: "Star catalogue", level: .advanced, choice: "local-gaia",
      of: PlateSolveProcess.catalogues),
  ])

  package let params: ParamSet

  package init(params: ParamSet, device: MTLDevice) throws {
    self.params = params
  }

  /// Unticked, nothing to run: the step is the image itself.
  package static func runsTool(_ params: ParamSet) -> Bool { params.flag("enabled") }

  /// The image as it is (the preview; Siril's result is the step).
  package func render(
    _ input: GPUImage, stats: LayerStats, into output: GPUImage, context: RenderContext
  ) throws {
    try ColourKernel.copy(input, into: output, commands: context.commands)
  }
}
