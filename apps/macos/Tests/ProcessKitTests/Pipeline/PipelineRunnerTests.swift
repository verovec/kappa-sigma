import Foundation
import ImageKit
import Metal
import ProcessKit
import RenderKit
import Synchronization
import TestSupport
import Testing

/// `PipelineRunner` (card 0059): a pipeline of recipes applied through a `History`, halting at
/// its breakpoints, keeping locked steps on replay, replayed on another bundle.
@Suite(
  "Pipeline runner — breakpoints, locked steps, replay on a new bundle",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct PipelineRunnerTests {
  /// The events of a run, collected from whatever task reports them.
  final class EventLog: Sendable {
    private let storage = Mutex<[PipelineRunner.Event]>([])
    var events: [PipelineRunner.Event] { storage.withLock { $0 } }
    var sink: PipelineRunner.EventSink { { event in self.storage.withLock { $0.append(event) } } }
  }

  static func registry() throws -> ProcessRegistry {
    try ProcessRegistry([DummyGain.self, ChannelCombinationProcess.self, StretchProcess.self])
  }

  /// A gain step: out = in · gain (the fixture's shift moves pixels, not values).
  static func gain(
    _ gain: Double, _ mode: PipelineStep.Mode = .auto, locked: Bool = false
  ) throws -> PipelineStep {
    var params = ParamSet(schema: DummyGain.schema)
    try params.set("gain", .number(gain))
    return PipelineStep(
      recipe: Recipe(processID: DummyGain.id, params: params), mode: mode, locked: locked)
  }

  static func image(_ value: Float, planes: Int = 1) -> AstroImage {
    AstroImage(
      width: 4, height: 2,
      planes: Array(repeating: [Float](repeating: value, count: 8), count: planes),
      metadata: ImageMetadata(rowOrder: .topDown))
  }

  static var bundle: PipelineBundle {
    PipelineBundle(
      stats: LayerStats(channels: [ChannelStats(median: 0.1, madn: 0.01, minimum: 0, maximum: 1)]))
  }

  static func runner(batch: [String: PipelineRunner.BatchProcess] = [:]) throws -> PipelineRunner {
    try PipelineRunner(
      registry: registry(), device: #require(MTLCreateSystemDefaultDevice()), batch: batch)
  }

  static func folder(_ name: String) throws -> URL {
    try ScratchDirectory.url.appendingPathComponent(name)
  }

  static func step(_ id: String, _ params: ParamSet = ParamSet(schema: ParamSchema([])))
    -> PipelineStep
  {
    PipelineStep(recipe: Recipe(processID: id, params: params))
  }

  @Test(
    "steps [auto, stop, auto] halt before the stop with it loaded; Continue finishes",
    .scratchDirectory)
  func testStopsAtBreakpoint() async throws {
    let pipeline = Pipeline(
      name: "M31", steps: [try Self.gain(2), try Self.gain(3, .stop), try Self.gain(0.5)])
    let history = try History(directory: try Self.folder("h"), original: Self.image(0.1))
    let runner = try Self.runner()
    let log = EventLog()
    let first = try await runner.run(pipeline, on: history, bundle: Self.bundle, onEvent: log.sink)
    #expect(first == .stopped(at: 1))
    #expect(history.steps.count == 1, "the stop step is loaded, not applied")
    #expect(log.events == [.applied(0), .stopped(1)])
    #expect(abs(history.current.planes[0][0] - 0.2) < 1e-6)

    let done = try await runner.resume(pipeline, at: 1, on: history, bundle: Self.bundle)
    #expect(done == .finished)
    #expect(history.steps.map(\.processID) == Array(repeating: DummyGain.id, count: 3))
    #expect(abs(history.current.planes[0][0] - 0.3) < 1e-6)
  }

  @Test("Continue applies the stop step with the values the user edited", .scratchDirectory)
  func testResumeWithEditedValues() async throws {
    let pipeline = Pipeline(name: "M31", steps: [try Self.gain(3, .stop)])
    let history = try History(directory: try Self.folder("h"), original: Self.image(0.1))
    let runner = try Self.runner()
    #expect(try await runner.run(pipeline, on: history, bundle: Self.bundle) == .stopped(at: 0))
    var edited = ParamSet(schema: DummyGain.schema)
    try edited.set("gain", .number(5))
    _ = try await runner.resume(pipeline, at: 0, on: history, bundle: Self.bundle, params: edited)
    #expect(abs(history.current.planes[0][0] - 0.5) < 1e-6)
    #expect(history.steps.last?.params == edited)
  }

  @Test("a locked step keeps its prior output on replay while the others re-run", .scratchDirectory)
  func testLockedStepNotReplayed() async throws {
    let recorded = Pipeline(
      name: "M31", steps: [try Self.gain(2), try Self.gain(1), try Self.gain(1.5)])
    let runner = try Self.runner()
    let first = try History(directory: try Self.folder("a"), original: Self.image(0.1))
    _ = try await runner.run(recorded, on: first, bundle: Self.bundle)

    // The middle step is locked, and its values changed since: replay keeps what was applied.
    var replayed = recorded
    replayed.steps[1] = try Self.gain(4, locked: true)
    let log = EventLog()
    let second = try await runner.replay(
      replayed, on: Self.image(0.1), in: try Self.folder("b"), bundle: Self.bundle,
      previous: PipelineRun(history: first, bundle: Self.bundle),
      onEvent: log.sink)
    #expect(log.events == [.applied(0), .reused(1), .applied(2)])
    #expect(try second.history.output(ofStep: 1).planes == first.output(ofStep: 1).planes)
    #expect(second.history.steps[1].params == first.steps[1].params, "the step as it was applied")
    #expect(try second.history.output(ofStep: 2).planes == first.output(ofStep: 2).planes)
  }

  @Test(
    "a locked step re-runs when its input differs: another bundle, a changed earlier step",
    .scratchDirectory)
  func testLockedStepNeedsTheSameInput() async throws {
    let recorded = Pipeline(name: "M31", steps: [try Self.gain(2), try Self.gain(3, locked: true)])
    let runner = try Self.runner()
    let first = try History(directory: try Self.folder("a"), original: Self.image(0.1))
    _ = try await runner.run(recorded, on: first, bundle: Self.bundle)

    let otherBundle = EventLog()
    _ = try await runner.replay(
      recorded, on: Self.image(0.2), in: try Self.folder("b"), bundle: Self.bundle,
      previous: PipelineRun(history: first, bundle: Self.bundle),
      onEvent: otherBundle.sink)
    #expect(otherBundle.events == [.applied(0), .applied(1)])

    var changed = recorded
    changed.steps[0] = try Self.gain(4)
    let changedStep = EventLog()
    _ = try await runner.replay(
      changed, on: Self.image(0.1), in: try Self.folder("c"), bundle: Self.bundle,
      previous: PipelineRun(history: first, bundle: Self.bundle),
      onEvent: changedStep.sink)
    #expect(changedStep.events == [.applied(0), .applied(1)])
  }

  @Test("Continue keeps taking locked steps from the previous history", .scratchDirectory)
  func testResumeKeepsLockedSteps() async throws {
    let recorded = Pipeline(
      name: "M31", steps: [try Self.gain(2), try Self.gain(3), try Self.gain(1.5)])
    let runner = try Self.runner()
    let first = try History(directory: try Self.folder("a"), original: Self.image(0.1))
    _ = try await runner.run(recorded, on: first, bundle: Self.bundle)

    let staged = Pipeline(
      name: "M31",
      steps: [try Self.gain(2), try Self.gain(3, .stop), try Self.gain(9, locked: true)])
    let replay = try await runner.replay(
      staged, on: Self.image(0.1), in: try Self.folder("b"), bundle: Self.bundle,
      previous: PipelineRun(history: first, bundle: Self.bundle))
    #expect(replay.outcome == .stopped(at: 1))
    let log = EventLog()
    _ = try await runner.resume(
      staged, at: 1, on: replay.history, bundle: Self.bundle,
      previous: PipelineRun(history: first, bundle: Self.bundle), onEvent: log.sink)
    #expect(log.events == [.applied(1), .reused(2)])
    #expect(try replay.history.output(ofStep: 2).planes == first.output(ofStep: 2).planes)
  }

  @Test(
    "a pipeline recorded on bundle A replays on bundle B: same recipes, other images",
    .scratchDirectory)
  func testReplayOnNewBundle() async throws {
    let pipeline = Pipeline(name: "M31", steps: [try Self.gain(2), try Self.gain(1)])
    let runner = try Self.runner()
    let bundleA = try await runner.replay(
      pipeline, on: Self.image(0.1), in: try Self.folder("a"), bundle: Self.bundle)
    let bundleB = try await runner.replay(
      pipeline, on: Self.image(0.3), in: try Self.folder("b"), bundle: Self.bundle)
    #expect(bundleA.outcome == .finished && bundleB.outcome == .finished)
    #expect(bundleA.history.steps.map(\.processID) == bundleB.history.steps.map(\.processID))
    #expect(bundleA.history.steps.map(\.params) == bundleB.history.steps.map(\.params))
    #expect(bundleA.history.current.planes != bundleB.history.current.planes)
    #expect(abs(bundleB.history.current.planes[0][0] - 0.6) < 1e-6)
  }

  @Test(
    "the bundle's layers reach a process that reads them (channel combination)", .scratchDirectory)
  func testLayersReachSteps() async throws {
    let combination = Pipeline(
      name: "M31", steps: [Self.step(ChannelCombinationProcess.id, try Palette.natural.params())])
    let runner = try Self.runner()
    var bundle = Self.bundle
    bundle.layers = ["RGB": Self.image(0.4, planes: 3)]
    let result = try await runner.replay(
      combination, on: Self.image(0.4, planes: 3), in: try Self.folder("a"), bundle: bundle)
    #expect(result.history.steps.count == 1)
    await #expect(throws: ProcessError.self) {
      _ = try await runner.replay(
        combination, on: Self.image(0.4, planes: 3), in: try Self.folder("b"), bundle: Self.bundle)
    }
  }

  @Test(
    "a batch process (a host tool) runs through its closure, its progress as it goes",
    .scratchDirectory)
  func testBatchStep() async throws {
    let batch = PipelineRunner.BatchProcess(schema: ParamSchema([])) { image, _, progress in
      progress(0.5)
      return AstroImage(
        width: image.width, height: image.height, planes: image.planes.map { $0.map { 1 - $0 } },
        metadata: image.metadata)
    }
    let pipeline = Pipeline(name: "M31", steps: [Self.step("invert-tool")])
    let log = EventLog()
    let result = try await Self.runner(batch: ["invert-tool": batch]).replay(
      pipeline, on: Self.image(0.25), in: try Self.folder("h"), bundle: Self.bundle,
      onEvent: log.sink)
    #expect(log.events == [.progress(0, 0.5), .applied(0)])
    #expect(abs(result.history.current.planes[0][0] - 0.75) < 1e-6)
  }

  @Test(
    "a step whose process is unknown, or whose values are refused, stops the run by name",
    .scratchDirectory)
  func testRefusals() async throws {
    let unknown = Pipeline(name: "M31", steps: [Self.step("nope")])
    await #expect(throws: PipelineError.unknownProcess("nope")) {
      _ = try await Self.runner().replay(
        unknown, on: Self.image(0.1), in: try Self.folder("a"), bundle: Self.bundle)
    }
    let flagSchema = ParamSchema([ParamSpec(id: "gain", title: "Gain", level: .simple, flag: true)])
    let wrongKind = Pipeline(
      name: "M31", steps: [Self.step(DummyGain.id, ParamSet(schema: flagSchema))])
    await #expect(throws: PipelineError.invalidValues(step: 0, ids: ["gain"])) {
      _ = try await Self.runner().replay(
        wrongKind, on: Self.image(0.1), in: try Self.folder("b"), bundle: Self.bundle)
    }
  }
}
