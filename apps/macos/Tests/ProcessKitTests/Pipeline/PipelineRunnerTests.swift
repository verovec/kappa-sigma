import Foundation
import ImageKit
import Metal
import ProcessKit
import TestSupport
import Testing

/// `PipelineRunner` (card 0059): a pipeline of recipes applied through a `History`, halting at
/// its breakpoints, keeping locked steps on replay, replayed on another bundle.
@Suite(
  "Pipeline runner — breakpoints, locked steps, replay on a new bundle",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct PipelineRunnerTests {
  static func registry() throws -> ProcessRegistry {
    try ProcessRegistry([DummyGain.self])
  }

  /// A gain step: out = in · gain + shift.
  static func gain(
    _ gain: Double, shift: Double = 0, _ mode: PipelineStep.Mode = .auto,
    locked: Bool = false
  ) throws -> PipelineStep {
    var params = ParamSet(schema: DummyGain.schema)
    try params.set("gain", .number(gain))
    try params.set("shift", .number(shift))
    return PipelineStep(
      recipe: Recipe(processID: DummyGain.id, params: params), mode: mode, locked: locked)
  }

  static func image(_ value: Float) -> AstroImage {
    AstroImage(
      width: 4, height: 2, planes: [[Float](repeating: value, count: 8)],
      metadata: ImageMetadata(rowOrder: .topDown))
  }

  static let stats = LayerStats(channels: [
    ChannelStats(median: 0.1, madn: 0.01, minimum: 0, maximum: 1)
  ])

  static func runner() throws -> PipelineRunner {
    try PipelineRunner(
      registry: registry(), device: #require(MTLCreateSystemDefaultDevice()))
  }

  @Test(
    "steps [auto, stop, auto] halt before the stop with it loaded; Continue finishes",
    .scratchDirectory)
  func testStopsAtBreakpoint() async throws {
    let pipeline = Pipeline(
      name: "M31", steps: [try Self.gain(2), try Self.gain(3, .stop), try Self.gain(0.5)])
    let history = try History(
      directory: ScratchDirectory.url.appendingPathComponent("h"), original: Self.image(0.1))
    let runner = try Self.runner()
    var events: [PipelineRunner.Event] = []
    let first = try await runner.run(pipeline, on: history, stats: Self.stats) { events.append($0) }
    #expect(first == .stopped(at: 1))
    #expect(history.steps.count == 1, "the stop step is loaded, not applied")
    #expect(events == [.applied(0), .stopped(1)])
    #expect(abs(history.current.planes[0][0] - 0.2) < 1e-6)

    let done = try await runner.resume(pipeline, at: 1, on: history, stats: Self.stats)
    #expect(done == .finished)
    #expect(history.steps.map(\.processID) == Array(repeating: DummyGain.id, count: 3))
    #expect(abs(history.current.planes[0][0] - 0.3) < 1e-6)
  }

  @Test("Continue applies the stop step with the values the user edited", .scratchDirectory)
  func testResumeWithEditedValues() async throws {
    let pipeline = Pipeline(name: "M31", steps: [try Self.gain(3, .stop)])
    let history = try History(
      directory: ScratchDirectory.url.appendingPathComponent("h"), original: Self.image(0.1))
    let runner = try Self.runner()
    #expect(try await runner.run(pipeline, on: history, stats: Self.stats) == .stopped(at: 0))
    var edited = ParamSet(schema: DummyGain.schema)
    try edited.set("gain", .number(5))
    _ = try await runner.resume(pipeline, at: 0, on: history, stats: Self.stats, params: edited)
    #expect(abs(history.current.planes[0][0] - 0.5) < 1e-6)
    #expect(history.steps.last?.params == edited)
  }

  @Test("a locked step keeps its prior output on replay while the others re-run", .scratchDirectory)
  func testLockedStepNotReplayed() async throws {
    let recorded = Pipeline(
      name: "M31", steps: [try Self.gain(2), try Self.gain(1, shift: 0.05), try Self.gain(1.5)])
    let runner = try Self.runner()
    let first = try History(
      directory: ScratchDirectory.url.appendingPathComponent("a"), original: Self.image(0.1))
    _ = try await runner.run(recorded, on: first, stats: Self.stats)

    // The middle step is locked, and its values changed since: replay keeps what was applied.
    var replayed = recorded
    replayed.steps[1] = try Self.gain(4, locked: true)
    var events: [PipelineRunner.Event] = []
    let second = try await runner.replay(
      replayed, on: Self.image(0.1), in: ScratchDirectory.url.appendingPathComponent("b"),
      stats: Self.stats, previous: first
    ) { events.append($0) }
    #expect(events == [.applied(0), .reused(1), .applied(2)])
    #expect(try second.history.output(ofStep: 1).planes == first.output(ofStep: 1).planes)
    #expect(second.history.steps[1].params == first.steps[1].params, "the step as it was applied")
    #expect(try second.history.output(ofStep: 2).planes == first.output(ofStep: 2).planes)
  }

  @Test(
    "a pipeline recorded on bundle A replays on bundle B: same recipes, other images",
    .scratchDirectory)
  func testReplayOnNewBundle() async throws {
    let pipeline = Pipeline(name: "M31", steps: [try Self.gain(2), try Self.gain(1, shift: 0.1)])
    let runner = try Self.runner()
    let bundleA = try await runner.replay(
      pipeline, on: Self.image(0.1), in: ScratchDirectory.url.appendingPathComponent("a"),
      stats: Self.stats)
    let bundleB = try await runner.replay(
      pipeline, on: Self.image(0.3), in: ScratchDirectory.url.appendingPathComponent("b"),
      stats: Self.stats)
    #expect(bundleA.outcome == .finished && bundleB.outcome == .finished)
    #expect(bundleA.history.steps.map(\.processID) == bundleB.history.steps.map(\.processID))
    #expect(bundleA.history.steps.map(\.params) == bundleB.history.steps.map(\.params))
    #expect(bundleA.history.current.planes != bundleB.history.current.planes)
    #expect(abs(bundleB.history.current.planes[0][0] - 0.6) < 1e-6)
  }

  @Test(
    "a batch process (a host tool) runs through its closure with its progress", .scratchDirectory)
  func testBatchStep() async throws {
    let batch = PipelineRunner.BatchProcess(schema: ParamSchema([])) { image, _, progress in
      progress(0.5)
      return AstroImage(
        width: image.width, height: image.height, planes: image.planes.map { $0.map { 1 - $0 } },
        metadata: image.metadata)
    }
    let runner = try PipelineRunner(
      registry: Self.registry(), device: #require(MTLCreateSystemDefaultDevice()),
      batch: ["invert-tool": batch])
    let pipeline = Pipeline(
      name: "M31",
      steps: [
        PipelineStep(
          recipe: Recipe(processID: "invert-tool", params: ParamSet(schema: ParamSchema([]))),
          mode: .auto, locked: false)
      ])
    var events: [PipelineRunner.Event] = []
    let result = try await runner.replay(
      pipeline, on: Self.image(0.25), in: ScratchDirectory.url.appendingPathComponent("h"),
      stats: Self.stats
    ) { events.append($0) }
    #expect(events == [.progress(0, 0.5), .applied(0)])
    #expect(abs(result.history.current.planes[0][0] - 0.75) < 1e-6)
  }

  @Test(
    "a step whose process is neither registered nor a batch tool is refused, by name",
    .scratchDirectory)
  func testUnknownProcessRefused() async throws {
    let pipeline = Pipeline(
      name: "M31",
      steps: [
        PipelineStep(
          recipe: Recipe(processID: "nope", params: ParamSet(schema: ParamSchema([]))), mode: .auto,
          locked: false)
      ])
    await #expect(throws: PipelineError.unknownProcess("nope")) {
      _ = try await Self.runner().replay(
        pipeline, on: Self.image(0.1), in: ScratchDirectory.url.appendingPathComponent("h"),
        stats: Self.stats)
    }
  }
}
