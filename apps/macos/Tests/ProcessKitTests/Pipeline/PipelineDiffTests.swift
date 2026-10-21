import Foundation
import ProcessKit
import Testing

/// Pipelines compared step by step (card 0059): what the diff view lists.
@Suite("Pipeline diff — one entry per difference")
struct PipelineDiffTests {
  static func step(_ gain: Double, _ mode: PipelineStep.Mode = .auto, locked: Bool = false)
    throws -> PipelineStep
  {
    var params = ParamSet(schema: DummyGain.schema)
    try params.set("gain", .number(gain))
    return PipelineStep(
      recipe: Recipe(processID: DummyGain.id, params: params), mode: mode, locked: locked)
  }

  @Test("two pipelines differing in one parameter give exactly one entry with both values")
  func testParamDiff() throws {
    let lhs = Pipeline(name: "A", steps: [try Self.step(2), try Self.step(3)])
    let rhs = Pipeline(name: "B", steps: [try Self.step(2), try Self.step(4)])
    #expect(
      PipelineDiff.entries(lhs, rhs) == [
        PipelineDiff.Entry(
          step: 1, processID: DummyGain.id, change: .param("gain", .number(3), .number(4)))
      ])
    #expect(PipelineDiff.entries(lhs, lhs).isEmpty)
  }

  @Test("problems: an unknown process, a missing layer, a linear step after a non-linear one")
  func testProblems() throws {
    let registry = try ProcessRegistry([
      ChannelCombinationProcess.self, SaturationProcess.self, ColourBalanceProcess.self,
    ])
    func step(_ id: String) -> PipelineStep {
      PipelineStep(recipe: Recipe(processID: id, params: ParamSet(schema: ParamSchema([]))))
    }
    let pipeline = Pipeline(
      name: "M31",
      steps: [
        step("channel-combination"), step("saturation"), step("colour-balance"), step("starnet"),
        step("nope"),
      ])
    #expect(
      pipeline.problems(registry: registry, batch: ["starnet"], present: [.color])
        == [
          "step 3 (colour-balance): a linear process after a non-linear one",
          "step 5: unknown process nope",
        ])
    #expect(
      Pipeline(name: "M31", steps: [step("saturation"), step("colour-balance")])
        .problems(registry: registry, present: [.color]).count == 1)
    let afterStretch = try ProcessRegistry([StretchProcess.self, ColourBalanceProcess.self])
    #expect(
      Pipeline(name: "M31", steps: [step("stretch"), step("colour-balance")])
        .problems(registry: afterStretch, present: [.color])
        == ["step 2 (colour-balance): a linear process after a non-linear one"])
  }

  @Test("mode, lock, process, added and removed steps are each one entry")
  func testStepDiff() throws {
    let lhs = Pipeline(name: "A", steps: [try Self.step(2), try Self.step(3)])
    let rhs = Pipeline(
      name: "B", steps: [try Self.step(2, .stop, locked: true), try Self.step(3), try Self.step(5)])
    #expect(
      PipelineDiff.entries(lhs, rhs) == [
        PipelineDiff.Entry(step: 0, processID: DummyGain.id, change: .mode(.auto, .stop)),
        PipelineDiff.Entry(step: 0, processID: DummyGain.id, change: .locked(false, true)),
        PipelineDiff.Entry(step: 2, processID: DummyGain.id, change: .added),
      ])
    #expect(
      PipelineDiff.entries(rhs, lhs).last
        == PipelineDiff.Entry(step: 2, processID: DummyGain.id, change: .removed))
  }
}
