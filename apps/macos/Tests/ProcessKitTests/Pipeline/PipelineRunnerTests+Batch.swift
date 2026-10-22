import Foundation
import ImageKit
import Metal
import ProcessKit
import TestSupport
import Testing

/// A batch tool that writes a layer (card 0091: StarNet's starless) keeps the working image and
/// records its output as the step's layer, in a pipeline and in the Studio alike.
extension PipelineRunnerTests {
  /// A « starless » tool: the image halved, written as the `starless` layer.
  static let halving = PipelineRunner.BatchProcess(
    schema: ParamSchema([]), writes: .starless, run: halve)

  @Sendable static func halve(
    _ image: AstroImage, _: ParamSet, progress: @escaping @Sendable (Double) -> Void
  ) async throws -> AstroImage {
    progress(0.25)
    progress(1)
    return AstroImage(
      width: image.width, height: image.height, planes: image.planes.map { $0.map { $0 / 2 } },
      metadata: image.metadata)
  }

  @Test(
    "a batch tool writing a layer keeps the head and records the layer as the step's output",
    .scratchDirectory)
  func testBatchStepWritesALayer() async throws {
    let pipeline = Pipeline(name: "M31", steps: [Self.step("halve-tool")])
    let log = EventLog()
    let result = try await Self.runner(batch: ["halve-tool": Self.halving]).replay(
      pipeline, on: Self.image(0.5), in: try Self.folder("a"), bundle: Self.bundle,
      onEvent: log.sink)

    #expect(log.events == [.progress(0, 0.25), .progress(0, 1), .applied(0)])
    #expect(result.history.current.planes == Self.image(0.5).planes)
    #expect(result.history.steps.map(\.outputs.keys.first) == [.starless])
    let starless = try #require(try result.history.layers()[.starless])
    #expect(starless.planes == Self.image(0.25).planes)
  }

  @Test("the Studio records a batch step the same way, its progress as it goes", .scratchDirectory)
  func testStudioBatchStep() async throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let history = try History(directory: try Self.folder("b"), original: Self.image(0.5))
    let session = try StudioSession(
      history: history, bundle: Self.bundle, registry: Self.registry(), device: device)
    let log = EventLog()

    try await session.apply(
      Self.halving, id: "halve-tool", params: ParamSet(schema: ParamSchema([]))
    ) { log.sink(.progress(0, $0)) }

    #expect(log.events == [.progress(0, 0.25), .progress(0, 1)])
    #expect(history.steps.map(\.processID) == ["halve-tool"])
    #expect(history.current.planes == Self.image(0.5).planes)
    #expect(session.presentRoles(base: []) == [.starless])
  }

  @Test("a locked batch step reused on replay keeps the layer it wrote", .scratchDirectory)
  func testReusedBatchStepKeepsItsLayer() async throws {
    var step = Self.step("halve-tool")
    step.locked = true
    let pipeline = Pipeline(name: "M31", steps: [step])
    let runner = try Self.runner(batch: ["halve-tool": Self.halving])
    let first = try History(directory: try Self.folder("a"), original: Self.image(0.5))
    _ = try await runner.run(pipeline, on: first, bundle: Self.bundle)
    let log = EventLog()

    let replay = try await runner.replay(
      pipeline, on: Self.image(0.5), in: try Self.folder("b"), bundle: Self.bundle,
      previous: PipelineRun(history: first, bundle: Self.bundle), onEvent: log.sink)

    #expect(log.events == [.reused(0)])
    let starless = try #require(try replay.history.layers()[.starless])
    #expect(starless.planes == Self.image(0.25).planes)
  }

  /// A « starless » tool writing the image times `factor`.
  static func scaling(_ factor: Float) -> PipelineRunner.BatchProcess {
    PipelineRunner.BatchProcess(
      schema: ParamSchema([]), writes: .starless,
      run: { image, _, _ in
        AstroImage(
          width: image.width, height: image.height,
          planes: image.planes.map { $0.map { $0 * factor } }, metadata: image.metadata)
      })
  }

  @Test(
    "a Studio render reads the step layers the history holds now, cached or not", .scratchDirectory)
  func testOverlayFollowsTheHistory() async throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let registry = try ProcessRegistry.standard()
    let history = try History(directory: try Self.folder("c"), original: Self.image(0.5, planes: 3))
    let session = try StudioSession(
      history: history, bundle: Self.bundle, registry: registry, device: device)
    var params = ParamSet(schema: StarRecompositionProcess.schema)
    // No stars put back: the render is the starless itself.
    try params.set("presence", .number(0))
    let none = ParamSet(schema: ParamSchema([]))

    try await session.apply(Self.scaling(0.5), id: "tool", params: none) { _ in }
    let first = try session.render(StarRecompositionProcess.id, params: params)
    try history.undo()
    try await session.apply(Self.scaling(0.25), id: "tool", params: none) { _ in }
    let second = try session.render(StarRecompositionProcess.id, params: params)

    let fresh = try StudioSession(
      history: history, bundle: Self.bundle, registry: registry, device: device)
    #expect(second.planes == (try fresh.render(StarRecompositionProcess.id, params: params)).planes)
    #expect(second.planes != first.planes)
  }
}
