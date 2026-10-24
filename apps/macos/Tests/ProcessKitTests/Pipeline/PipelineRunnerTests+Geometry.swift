import Foundation
import ImageKit
import Metal
import ProcessKit
import TestSupport
import Testing

extension PipelineRunnerTests {
  /// Card 0090: a geometry step in a pipeline moves the bundle's layers like the Studio does, so
  /// the steps after it read layers of the new size; a locked geometry step reused on replay
  /// brings its moved layers too.
  @Test(
    "a pipeline's geometry step moves the layers; a locked replay reuses them", .scratchDirectory)
  func testGeometryMovesLayers() async throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let runner = try PipelineRunner(
      registry: ProcessRegistry([GeometryProcess.self, DummyGain.self]), device: device)
    let bundle = PipelineBundle(
      stats: Self.bundle.stats, layers: ["RGB": Self.image(0.3, planes: 3), "Ha": Self.image(0.6)])
    var params = ParamSet(schema: GeometryProcess.schema)
    try params.set("cropLeft", .number(1))
    try params.set("rotation", .choice("90"))
    let geometry = PipelineStep(
      recipe: Recipe(processID: GeometryProcess.id, params: params), locked: true)
    let pipeline = Pipeline(name: "crop", steps: [geometry, try Self.gain(2)])

    let history = try History(directory: try Self.folder("first"), original: Self.image(0.1))
    #expect(try await runner.run(pipeline, on: history, bundle: bundle) == .finished)
    #expect(history.current.width == 2 && history.current.height == 3)
    let layers = try history.writtenLayers()
    #expect(layers.keys.sorted() == ["Ha", "RGB"])
    #expect(layers.values.allSatisfy { $0.width == 2 && $0.height == 3 })

    let log = EventLog()
    let replay = try await runner.replay(
      pipeline, on: Self.image(0.1), in: try Self.folder("again"), bundle: bundle,
      previous: PipelineRun(history: history, bundle: bundle), onEvent: log.sink)
    #expect(log.events == [.reused(0), .applied(1)])
    #expect(try replay.history.writtenLayers().mapValues(\.planes) == layers.mapValues(\.planes))
  }
}

extension PipelineRunnerTests {
  /// Card 0106: a pipeline's geometry step is recorded as a move, so the steps after it drop
  /// the solutions it could not move; a locked replay reuses the step as a move.
  @Test("a pipeline records which steps moved the pixels, replayed too", .scratchDirectory)
  func testGeometryIsRecordedAsAMove() async throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let runner = try PipelineRunner(
      registry: ProcessRegistry([GeometryProcess.self, DummyGain.self]), device: device)
    var params = ParamSet(schema: GeometryProcess.schema)
    try params.set("flipV", .flag(true))
    let geometry = PipelineStep(
      recipe: Recipe(processID: GeometryProcess.id, params: params), locked: true)
    let pipeline = Pipeline(name: "flip", steps: [geometry, try Self.gain(2)])

    let history = try History(directory: try Self.folder("first"), original: Self.image(0.1))
    #expect(try await runner.run(pipeline, on: history, bundle: Self.bundle) == .finished)
    #expect(history.steps.map(\.movesPixels) == [true, false])

    let log = EventLog()
    let replay = try await runner.replay(
      pipeline, on: Self.image(0.1), in: try Self.folder("again"), bundle: Self.bundle,
      previous: PipelineRun(history: history, bundle: Self.bundle), onEvent: log.sink)
    #expect(log.events == [.reused(0), .applied(1)])
    #expect(replay.history.steps.map(\.movesPixels) == [true, false])
  }
}
