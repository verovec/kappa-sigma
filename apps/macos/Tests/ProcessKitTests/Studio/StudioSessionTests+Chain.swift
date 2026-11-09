import Foundation
import ImageKit
import Metal
import ProcessKit
import TestSupport
import Testing

/// Card 0158: the chain preview renders applied step k with new values, then the steps after it
/// with their recorded ones, in memory — the pixels a revise (0157) writes, nothing on disk.
@Suite(
  "StudioSession — the chain preview of a revised step",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct StudioSessionChainTests {
  /// A step as the Studio applies it: a process and its values.
  struct Step {
    let id: String
    let params: ParamSet
    var recipe: Recipe { Recipe(processID: id, params: params) }
  }

  static func registry() throws -> ProcessRegistry {
    try ProcessRegistry([
      DummyGain.self, StretchProcess.self, GeometryProcess.self, ChannelCombinationProcess.self,
      BackgroundExtractionProcess.self, DenoiseProcess.self,
    ])
  }

  /// A 4×2 colour ramp: no two pixels alike, so a moved or rescaled pixel shows.
  static func ramp(_ offset: Float = 0) -> AstroImage {
    AstroImage(
      width: 4, height: 2,
      planes: (0..<3).map { plane in
        (0..<8).map { Float($0) / 16 + Float(plane) / 32 + offset }
      },
      metadata: ImageMetadata(rowOrder: .topDown))
  }

  static var bundle: PipelineBundle {
    let rgb = ramp(0.05)
    let stats = StudioSession.stats(of: rgb)
    return PipelineBundle(stats: stats, layers: ["RGB": rgb], layerStats: ["RGB": stats])
  }

  static func session(_ name: String) throws -> StudioSession {
    let history = try History(
      directory: try ScratchDirectory.url.appendingPathComponent(name), original: ramp())
    return try StudioSession(
      history: history, bundle: bundle, registry: try registry(),
      device: try #require(MTLCreateSystemDefaultDevice()))
  }

  static func gain(_ gain: Double, shift: Double = 0) throws -> Step {
    var params = ParamSet(schema: DummyGain.schema)
    try params.set("gain", .number(gain))
    try params.set("shift", .number(shift))
    return Step(id: DummyGain.id, params: params)
  }

  static func stretch(_ target: Double) throws -> Step {
    var params = ParamSet(schema: StretchProcess.schema)
    try params.set("targetBackground", .number(target))
    return Step(id: StretchProcess.id, params: params)
  }

  static func crop() throws -> Step {
    var params = ParamSet(schema: GeometryProcess.schema)
    try params.set("cropLeft", .number(1))
    return Step(id: GeometryProcess.id, params: params)
  }

  static var combination: Step {
    Step(
      id: ChannelCombinationProcess.id, params: ParamSet(schema: ChannelCombinationProcess.schema))
  }

  /// `recipes` applied one by one through the session, as the Studio's Apply records them.
  static func applying(_ steps: [Step], on session: StudioSession) throws {
    for step in steps { try session.apply(step.id, params: step.params) }
  }

  /// `recipes` replayed on a new history by the pipeline runner: what a revise writes.
  static func replayed(_ steps: [Step], _ name: String, masks: [Int: AstroImage] = [:])
    async throws -> AstroImage
  {
    let session = try session(name)
    let runner = try PipelineRunner(registry: try registry(), device: session.device)
    _ = try await runner.run(
      Pipeline(name: "revise", steps: steps.map { PipelineStep(recipe: $0.recipe) }),
      on: session.history, bundle: session.bundle, masks: masks)
    return session.history.current
  }

  static func same(_ one: AstroImage, _ two: AstroImage) -> Bool {
    one.width == two.width && one.height == two.height
      && StudioSession.samePixels(one.planes, two.planes)
  }

  @Test(
    "testPreviewChain_EqualsApplyChain: step k with new values, the rest as recorded",
    .scratchDirectory, arguments: [0, 1, 2])
  func testPreviewChain_EqualsApplyChain(k: Int) async throws {
    let recorded = [try Self.gain(1.5, shift: 1), try Self.stretch(0.2), try Self.gain(0.8)]
    let edited = [try Self.gain(0.7, shift: 2), try Self.stretch(0.35), try Self.gain(1.3)][k]
    let session = try Self.session("applied")
    try Self.applying(recorded, on: session)

    let preview = try await session.previewChain(from: k, params: edited.params)

    var revised = recorded
    revised[k] = edited
    let expected = try await Self.replayed(revised, "scratch")
    #expect(preview.stoppedBefore == nil)
    #expect(Self.same(preview.image, expected), "bit-identical to the revise's replay")
    #expect(!Self.same(preview.image, session.history.current), "the new values show")
  }

  @Test("testPreviewChain_StopsBeforeHostTool", .scratchDirectory)
  func testPreviewChain_StopsBeforeHostTool() async throws {
    let session = try Self.session("applied")
    try Self.applying([try Self.gain(1.5), try Self.stretch(0.2)], on: session)
    try session.apply(
      BackgroundExtractionProcess.id, params: ParamSet(schema: BackgroundExtractionProcess.schema),
      result: Self.ramp(0.01), outputs: [.backgroundModel: Self.ramp(0.02)])
    try Self.applying([try Self.gain(0.9)], on: session)

    let preview = try await session.previewChain(from: 0, params: try Self.gain(0.6).params)

    #expect(preview.stoppedBefore == 2)
    let expected = try await Self.replayed([try Self.gain(0.6), try Self.stretch(0.2)], "scratch")
    #expect(Self.same(preview.image, expected), "the image just before the tool")
  }

  @Test("a host-tool step k itself stops the chain at k, on its input", .scratchDirectory)
  func testPreviewChain_ToolStepStopsAtItself() async throws {
    let session = try Self.session("applied")
    try Self.applying([try Self.gain(1.5)], on: session)
    let tool = ParamSet(schema: BackgroundExtractionProcess.schema)
    try session.apply(BackgroundExtractionProcess.id, params: tool, result: Self.ramp(0.01))

    let preview = try await session.previewChain(from: 1, params: tool)

    #expect(preview.stoppedBefore == 1)
    #expect(Self.same(preview.image, try session.history.output(ofStep: 0)))
  }

  @Test(
    "testPreviewChain_UsesChainLayers: a crop in the chain moves what the next reads",
    .scratchDirectory)
  func testPreviewChain_UsesChainLayers() async throws {
    let recorded = [try Self.gain(1.5), try Self.crop(), Self.combination]
    let session = try Self.session("applied")
    try Self.applying(recorded, on: session)

    let preview = try await session.previewChain(from: 0, params: try Self.gain(0.5).params)

    #expect(preview.image.width == 3, "the combination read the RGB layer the crop moved")
    let expected = try await Self.replayed(
      [try Self.gain(0.5), try Self.crop(), Self.combination], "scratch")
    #expect(Self.same(preview.image, expected))
  }

  @Test("testPreviewChain_LeavesHistoryUntouched", .scratchDirectory)
  func testPreviewChain_LeavesHistoryUntouched() async throws {
    let session = try Self.session("applied")
    try Self.applying([try Self.gain(1.5), try Self.crop(), try Self.gain(0.8)], on: session)
    let directory = session.history.directory
    let files = { try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() }
    let manifest = {
      try Data(
        contentsOf: directory.deletingLastPathComponent().appendingPathComponent("applied.json"))
    }
    let (steps, before, bytes, head) = (
      session.history.steps, try files(), try manifest(), session.history.current
    )

    for gain in [0.4, 0.6, 0.9] {
      _ = try await session.previewChain(from: 0, params: try Self.gain(gain).params)
    }

    #expect(session.history.steps == steps)
    #expect(try files() == before)
    #expect(try manifest() == bytes)
    #expect(Self.same(session.history.current, head))
  }

  @Test("the cached input of step k follows the history: an undo re-reads it", .scratchDirectory)
  func testPreviewChain_CacheFollowsTheHistory() async throws {
    let session = try Self.session("applied")
    try Self.applying([try Self.gain(1.5), try Self.gain(2), try Self.gain(0.5)], on: session)
    let edit = try Self.gain(1).params
    let first = try await session.previewChain(from: 2, params: edit)
    #expect(Self.same(first.image, try session.history.output(ofStep: 1)))

    try session.history.undo()
    try session.history.undo()
    try Self.applying([try Self.gain(3), try Self.gain(0.5)], on: session)
    let again = try await session.previewChain(from: 2, params: edit)

    #expect(Self.same(again.image, try session.history.output(ofStep: 1)), "the new step 1")
    #expect(!Self.same(again.image, first.image))
  }

  @Test("a branch move on the base layer starts the chain from its new head", .scratchDirectory)
  func testPreviewChain_BranchMoveRereadsInput() async throws {
    let session = try Self.session("applied")
    try Self.applying([try Self.gain(1.5)], on: session)
    let edit = try Self.gain(1).params
    let before = try await session.previewChain(from: 0, params: edit)

    try session.applyBranch(
      "RGB", DenoiseProcess.id, params: ParamSet(schema: DenoiseProcess.schema))
    let after = try await session.previewChain(from: 0, params: edit)

    #expect(!Self.same(after.image, before.image), "the original is the branch's new head")
  }

  @Test("a step out of the history is refused", .scratchDirectory)
  func testPreviewChain_NoStep() async throws {
    let session = try Self.session("applied")
    try Self.applying([try Self.gain(1.5)], on: session)
    await #expect(throws: HistoryError.self) {
      _ = try await session.previewChain(from: 1, params: try Self.gain(1).params)
    }
  }

  @Test("ending the edit drops the cached input", .scratchDirectory)
  func testEndChainPreview_DropsTheCache() async throws {
    let session = try Self.session("applied")
    try Self.applying([try Self.gain(1.5), try Self.gain(2)], on: session)
    _ = try await session.previewChain(from: 1, params: try Self.gain(1).params)
    #expect(session.chainInputFiles != nil)

    session.endChainPreview()

    #expect(session.chainInputFiles == nil)
  }

  /// A one-plane mask letting the left half through.
  static var halfMask: AstroImage {
    AstroImage(
      width: 4, height: 2, planes: [[1, 1, 0, 0, 1, 1, 0, 0]],
      metadata: ImageMetadata(rowOrder: .topDown))
  }

  @Test(
    "a masked step in the chain renders under its recorded mask, as the revise replays it",
    .scratchDirectory)
  func testPreviewChain_AppliesRecordedMasks() async throws {
    let session = try Self.session("applied")
    try Self.applying([try Self.gain(1.5)], on: session)
    let masked = try Self.gain(2)
    try session.apply(masked.id, params: masked.params, mask: Self.halfMask)

    let preview = try await session.previewChain(from: 0, params: try Self.gain(0.5).params)

    let expected = try await Self.replayed(
      [try Self.gain(0.5), masked], "scratch", masks: [1: Self.halfMask])
    #expect(Self.same(preview.image, expected))
    let unmasked = try await Self.replayed([try Self.gain(0.5), masked], "unmasked")
    #expect(!Self.same(preview.image, unmasked), "the mask shows")
  }

  @Test(
    "a crop k with a masked step after it is refused, as the revise refuses it",
    .scratchDirectory)
  func testPreviewChain_MovedMaskRefused() async throws {
    let session = try Self.session("applied")
    let flat = Step(id: GeometryProcess.id, params: ParamSet(schema: GeometryProcess.schema))
    try Self.applying([flat], on: session)
    let masked = try Self.gain(2)
    try session.apply(masked.id, params: masked.params, mask: Self.halfMask)

    await #expect(throws: PipelineError.maskMoved(step: 1)) {
      _ = try await session.previewChain(from: 0, params: try Self.crop().params)
    }
  }
}
