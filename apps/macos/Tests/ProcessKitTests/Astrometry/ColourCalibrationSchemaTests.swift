import Foundation
import ImageKit
import Metal
import ProcessKit
import TestSupport
import Testing

/// Card 0094: colour calibration's declaration — a host tool only when ticked, a solution
/// needed, Siril's names as choices.
@Suite("ColourCalibrationProcess: tool when ticked, solution needed, Siril's names")
struct ColourCalibrationSchemaTests {
  static func params(enabled: Bool) throws -> ParamSet {
    var params = ParamSet(schema: ColourCalibrationProcess.schema)
    try params.set("enabled", .flag(enabled))
    return params
  }

  @Test("ticked it runs Siril; unticked it is the image itself; a pipeline says so up front")
  func testRunsTool() throws {
    let type = ColourCalibrationProcess.self
    #expect(type.runsTool(try Self.params(enabled: true)))
    #expect(!type.runsTool(try Self.params(enabled: false)))
    #expect(type.requiresSolution && !PlateSolveProcess.requiresSolution)
    #expect(PlateSolveProcess.runsTool(ParamSet(schema: PlateSolveProcess.schema)))
    let registry = try ProcessRegistry([ColourCalibrationProcess.self])
    func pipeline(_ enabled: Bool) throws -> Pipeline {
      Pipeline(
        name: "colour",
        steps: [
          PipelineStep(
            recipe: Recipe(processID: type.id, params: try Self.params(enabled: enabled)))
        ])
    }
    #expect(
      try pipeline(true).stepProblems(registry: registry, present: [.color]) == [
        ["runs a host tool: apply it in the Studio"]
      ])
    #expect(try pipeline(false).stepProblems(registry: registry, present: [.color]) == [[]])
    // Card 0140: where a batch tool would run it, an unchosen sensor is refused up front.
    #expect(
      try pipeline(true).stepProblems(registry: registry, batch: [type.id], present: [.color])
        == [["choose sensor first"]])
  }

  @Test(
    "an unticked step runs in a pipeline without its tool: the image itself", .scratchDirectory,
    .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
  func testDisabledStepInPipeline() async throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let registry = try ProcessRegistry([ColourCalibrationProcess.self])
    let image = AstroImage(
      width: 2, height: 1, planes: [[0.1, 0.2], [0.3, 0.4], [0.5, 0.6]],
      metadata: ImageMetadata(rowOrder: .topDown))
    let stats = StudioSession.stats(of: image)
    let bundle = PipelineBundle(stats: stats, layers: ["RGB": image], layerStats: ["RGB": stats])
    let off = Pipeline(
      name: "off",
      steps: [
        PipelineStep(
          recipe: Recipe(
            processID: ColourCalibrationProcess.id, params: try Self.params(enabled: false)))
      ])
    let replay = try await PipelineRunner(registry: registry, device: device, batch: [:]).replay(
      off, on: image, in: try ScratchDirectory.url.appendingPathComponent("a"), bundle: bundle)
    #expect(replay.history.current.planes == image.planes)
    #expect(replay.history.steps.map(\.processID) == [ColourCalibrationProcess.id])
  }

  @Test("the defaults: no camera (card 0140), a white reference Siril lists, SPCC ticked")
  func testDefaults() {
    let params = ParamSet(schema: ColourCalibrationProcess.schema)
    #expect(params.choice("sensor").isEmpty && params.choice("filter").isEmpty)
    #expect(SPCCNames.whiteReferences.contains(params.choice("whiteReference")))
    #expect(params.choice("method") == "spcc" && params.flag("enabled"))
  }
}
