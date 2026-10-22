import Foundation
import ImageKit
import Metal
import ProcessKit
import TestSupport
import Testing

extension PipelineRunnerTests {
  /// The runner reads what the Studio reads (card 0088): a layer an earlier step wrote
  /// (StarNet's starless) is a context layer of the steps after it, as in `StudioSession`.
  @Test("a step reads the layers earlier steps wrote, as the Studio does", .scratchDirectory)
  func testStepOutputsAreContextLayers() async throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let registry = try ProcessRegistry([DummyGain.self, StarRecompositionProcess.self])
    let runner = try PipelineRunner(registry: registry, device: device)
    let history = try History(directory: try Self.folder("h"), original: Self.image(0.2, planes: 3))
    try history.apply(
      processID: DummyGain.id, params: ParamSet(schema: DummyGain.schema),
      result: Self.image(0.2, planes: 3), outputs: [.starless: Self.image(0.1, planes: 3)])
    let pipeline = Pipeline(
      name: "p",
      steps: [
        try Self.gain(1),
        Self.step(StarRecompositionProcess.id, ParamSet(schema: StarRecompositionProcess.schema)),
      ])
    let outcome = try await runner.run(pipeline, on: history, bundle: Self.bundle, from: 1)
    #expect(outcome == .finished)
    #expect(history.steps.map(\.processID) == [DummyGain.id, StarRecompositionProcess.id])
  }
}
