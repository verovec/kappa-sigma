import ProcessKit
import Testing

/// The roles a planned pipeline walks through (card 0137): a combination that makes three planes
/// makes a colour image for the steps after it, even on a mono bundle.
@Suite("Pipeline — the colour role after a planned combination")
struct PipelineProblemsTests {
  static func step(_ id: String) -> PipelineStep {
    PipelineStep(recipe: Recipe(processID: id, params: ParamSet(schema: ParamSchema([]))))
  }

  @Test(
    "a colour step on a mono bundle: greyed alone, offered after a planned combination",
    arguments: [
      ([LineInjectionProcess.id], [["needs a color layer"]]),
      ([ChannelCombinationProcess.id, LineInjectionProcess.id], [[], []]),
      // A combination that cannot run makes no colour image for the steps after it.
      (
        [StretchProcess.id, ChannelCombinationProcess.id, LineInjectionProcess.id],
        [
          [], ["a linear process after a non-linear one"],
          ["needs a color layer", "a linear process after a non-linear one"],
        ]
      ),
    ] as [([String], [[String]])])
  func testStepProblems_colourAfterCombination(ids: [String], expected: [[String]]) throws {
    let registry = try ProcessRegistry([
      ChannelCombinationProcess.self, LineInjectionProcess.self, StretchProcess.self,
    ])
    let pipeline = Pipeline(name: "mono", steps: ids.map(Self.step))
    #expect(
      pipeline.stepProblems(registry: registry, present: [.luminance, .emission]) == expected)
  }
}
