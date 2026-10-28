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

extension PipelineDiffTests {
  @Test("the same problems, one list per step, for the sidebar's greyed rows")
  func testStepProblems() throws {
    let registry = try ProcessRegistry([
      ChannelCombinationProcess.self, SaturationProcess.self, ColourBalanceProcess.self,
      StarRecompositionProcess.self,
    ])
    func step(_ id: String) -> PipelineStep {
      PipelineStep(recipe: Recipe(processID: id, params: ParamSet(schema: ParamSchema([]))))
    }
    let pipeline = Pipeline(
      name: "M31",
      steps: [
        step("channel-combination"), step("saturation"), step("colour-balance"),
        step("star-recomposition"), step("nope"),
      ])
    let problems = pipeline.stepProblems(registry: registry, present: [.color])
    #expect(problems.count == 5 && problems[0].isEmpty && problems[1].isEmpty)
    #expect(problems[2] == ["a linear process after a non-linear one"])
    #expect(problems[3].count == 1 && problems[4] == ["unknown process nope"])
  }
}

extension PipelineDiffTests {
  @Test(
    "testNewDefaultsAreNotDifferences: a pipeline saved before Hβ/[NII] loads with their defaults")
  func testNewDefaultsAreNotDifferences() throws {
    let registry = try ProcessRegistry([EmissionScreensProcess.self, LineInjectionProcess.self])
    let types: [any ImageProcess.Type] = [EmissionScreensProcess.self, LineInjectionProcess.self]
    let current = Pipeline(
      name: "finish",
      steps: types.map { type in
        PipelineStep(recipe: Recipe(processID: type.id, params: ParamSet(schema: type.schema)))
      })
    // The same file as written before card 0141: no hb… / nii… entries.
    let data = try current.json()
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let steps = try #require(object["steps"] as? [[String: Any]])
    object["steps"] = try steps.map { step in
      var step = step
      var recipe = try #require(step["recipe"] as? [String: Any])
      let params = try #require(recipe["params"] as? [[String: Any]])
      recipe["params"] = params.filter { entry in
        let id = entry["id"] as? String ?? ""
        return !id.hasPrefix("hb") && !id.hasPrefix("nii")
      }
      step["recipe"] = recipe
      return step
    }
    let old = try Pipeline.load(
      try JSONSerialization.data(withJSONObject: object), registry: registry)
    #expect(old.warnings.isEmpty)
    #expect(PipelineDiff.entries(old.pipeline, current).isEmpty)
    // Not vacuous: the old file had 28 fewer entries (8 screens + 6 injection, per line).
    let count = { (steps: [[String: Any]]) in
      steps.map { (($0["recipe"] as? [String: Any])?["params"] as? [Any])?.count ?? 0 }
        .reduce(0, +)
    }
    #expect(count(steps) - count(object["steps"] as? [[String: Any]] ?? []) == 28)
  }
}
