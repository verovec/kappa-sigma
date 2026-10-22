import Foundation
import ImageKit
import Metal
import ProcessKit
import TestSupport
import Testing

extension PipelineRunnerTests {
  /// A batch step rewriting the bundle's RGB to `value` and writing a background model.
  static func rewriteRGB(_ value: Float) -> PipelineRunner.BatchProcess {
    PipelineRunner.BatchProcess(schema: ParamSchema([])) { input, _, _ in
      PipelineRunner.BatchOutput(
        result: input.image, outputs: [.backgroundModel: Self.image(0.01, planes: 3)],
        replaced: ["RGB": Self.image(value, planes: 3)])
    }
  }

  static var rgbBundle: PipelineBundle {
    let rgb = Self.image(0.2, planes: 3)
    return PipelineBundle(
      stats: StudioSession.stats(of: rgb), layers: ["RGB": rgb],
      layerStats: ["RGB": StudioSession.stats(of: rgb)])
  }

  /// Card 0092: a GPU step after a batch step reads the layers it rewrote, as in the Studio.
  @Test("a GPU step reads the bundle layer an earlier batch step rewrote", .scratchDirectory)
  func testGPUStepReadsRewrittenLayer() async throws {
    let pipeline = Pipeline(
      name: "M31", steps: [Self.step("rewrite"), Self.step(ChannelCombinationProcess.id)])
    let result = try await Self.runner(batch: ["rewrite": Self.rewriteRGB(0.7)]).replay(
      pipeline, on: Self.image(0.2, planes: 3), in: try Self.folder("h"), bundle: Self.rgbBundle)
    #expect(result.history.steps.count == 2)
    #expect(result.history.current.planes.allSatisfy { $0.allSatisfy { abs($0 - 0.7) < 1e-6 } })
  }

  /// Card 0092: a locked batch step reused on replay keeps the layers it wrote and rewrote.
  @Test("a reused locked batch step carries its outputs and rewritten layers", .scratchDirectory)
  func testReusedBatchStepKeepsLayers() async throws {
    var step = Self.step("rewrite")
    step.locked = true
    let pipeline = Pipeline(name: "M31", steps: [step])
    let runner = try Self.runner(batch: ["rewrite": Self.rewriteRGB(0.7)])
    let first = try await runner.replay(
      pipeline, on: Self.image(0.2, planes: 3), in: try Self.folder("a"), bundle: Self.rgbBundle)
    let log = EventLog()
    let second = try await runner.replay(
      pipeline, on: Self.image(0.2, planes: 3), in: try Self.folder("b"), bundle: Self.rgbBundle,
      previous: PipelineRun(history: first.history, bundle: Self.rgbBundle), onEvent: log.sink)
    #expect(log.events == [.reused(0)])
    let written = try second.history.writtenLayers()
    #expect(written["RGB"]?.planes[0][0] == 0.7)
    #expect(written["backgroundModel"] != nil)
  }
}
