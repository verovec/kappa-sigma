import Foundation
import ImageKit
import ProcessKit
import TestSupport
import Testing

/// Card 0160: the Studio's replay hands the runner the masks its steps were applied under, by
/// index; a recipe carries none, so a pipeline on its own runs unmasked.
extension PipelineRunnerTests {
  @Test("testRun_WithMasks_AppliesAndRecordsEachStepsMask", .scratchDirectory)
  func testRun_WithMasks_AppliesAndRecordsEachStepsMask() async throws {
    let pipeline = Pipeline(name: "replay", steps: [try Self.gain(2), try Self.gain(3)])
    let history = try History(directory: try Self.folder("h"), original: Self.image(0.1))
    let mask = AstroImage(
      width: 4, height: 2, planes: [[1, 1, 1, 1, 0, 0, 0, 0]],
      metadata: ImageMetadata(rowOrder: .topDown))

    _ = try await Self.runner().run(pipeline, on: history, bundle: Self.bundle, masks: [1: mask])

    #expect(history.steps[0].mask == nil && history.steps[1].mask != nil)
    #expect(try history.mask(ofStep: 1)?.planes == mask.planes)
    let pixels = history.current.planes[0]
    #expect(pixels[..<4].allSatisfy { abs($0 - 0.6) < 1e-6 }, "let through: 0.1 · 2 · 3")
    #expect(pixels[4...].allSatisfy { abs($0 - 0.2) < 1e-6 }, "held back: 0.1 · 2")
  }

  @Test("testRun_ReusedLockedStep_KeepsItsMask", .scratchDirectory)
  func testRun_ReusedLockedStep_KeepsItsMask() async throws {
    let recorded = Pipeline(name: "M31", steps: [try Self.gain(2), try Self.gain(3)])
    let runner = try Self.runner()
    let mask = AstroImage(
      width: 4, height: 2, planes: [[1, 1, 1, 1, 0, 0, 0, 0]],
      metadata: ImageMetadata(rowOrder: .topDown))
    let first = try History(directory: try Self.folder("a"), original: Self.image(0.1))
    _ = try await runner.run(recorded, on: first, bundle: Self.bundle, masks: [1: mask])

    var replayed = recorded
    replayed.steps[1] = try Self.gain(3, locked: true)
    let second = try await runner.replay(
      replayed, on: Self.image(0.1), in: try Self.folder("b"), bundle: Self.bundle,
      previous: PipelineRun(history: first, bundle: Self.bundle))

    #expect(try second.history.mask(ofStep: 1)?.planes == mask.planes, "reused with its mask")
    #expect(try second.history.output(ofStep: 1).planes == first.output(ofStep: 1).planes)
  }
}
