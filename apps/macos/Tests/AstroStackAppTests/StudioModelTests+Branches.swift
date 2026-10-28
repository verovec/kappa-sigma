import AppKit
import AstroStackApp
import CryptoKit
import Foundation
import ImageKit
import Metal
import ProcessKit
import ProjectKit
import TestSupport
import Testing

/// The main history over branches (card 0118): untouched branches change nothing, a branch edit
/// marks the main steps that read it stale, and Replay re-applies them with their values.
@MainActor
@Suite(
  "StudioModel — branches under the main history",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
struct StudioModelBranchTests {
  /// Combination, stretch, screens: the main steps of a BB + DB finish.
  static func finish(_ model: StudioModel) throws {
    try model.apply(StretchProcess.id, params: ParamSet(schema: StretchProcess.schema))
    try model.apply(
      EmissionScreensProcess.id, params: ParamSet(schema: EmissionScreensProcess.schema))
  }

  /// SHA-256 of `history.json` after combination + stretch + screens on `BranchTests.bundle()`,
  /// recorded with the code before card 0118 (254 lines, no `branchHeads` key), re-recorded by
  /// card 0141: the screens' Hβ and [NII] defaults added (318 lines); without those 16 entries
  /// the file still hashes to the 0118 digest `3410e49c…534f`.
  static let recordedManifestSHA256 =
    "b33d1729613299c584c467998a3847bfb3ad0741b263659b1bddd5691dd19f63"

  @Test("testNoBranchStepKeepsMainByteIdentical", .scratchDirectory)
  func testNoBranchStepKeepsMainByteIdentical() async throws {
    let opened = try BranchTests.project()
    defer { try? opened.package.close() }
    let model = try BranchTests.model(opened)
    try Self.finish(model)

    let manifest = try Data(contentsOf: opened.folder.appendingPathComponent("history.json"))
    let digest = SHA256.hash(data: manifest).map { String(format: "%02x", $0) }.joined()
    #expect(digest == Self.recordedManifestSHA256)
    let branches = opened.folder.appendingPathComponent("branches")
    #expect(!FileManager.default.fileExists(atPath: branches.path), "no branch folder written")
    // The same steps through the pipeline runner on the bare bundle (no branch seam): the same
    // bytes, step by step, on this GPU.
    let device = try #require(MTLCreateSystemDefaultDevice())
    let runner = try PipelineRunner(registry: ProcessRegistry.standard(), device: device)
    let bundle = BranchTests.bundle()
    let steps = model.steps.map {
      PipelineStep(recipe: Recipe(processID: $0.processID, params: $0.params))
    }
    let replay = try await runner.replay(
      Pipeline(name: "bare", steps: steps), on: try #require(bundle.layers["RGB"]),
      in: try ScratchDirectory.url.appendingPathComponent("bare"), bundle: bundle)
    for step in model.steps {
      let ours = model.session.history.directory.appendingPathComponent(step.file)
      let bare = replay.history.directory.appendingPathComponent(step.file)
      #expect(try Data(contentsOf: ours) == Data(contentsOf: bare), "\(step.file) identical")
    }
  }

  @Test("testBranchEditMarksMainStale_ReplayKeepsValues", .scratchDirectory)
  func testBranchEditMarksMainStale_ReplayKeepsValues() async throws {
    let opened = try BranchTests.project()
    defer { try? opened.package.close() }
    let model = try BranchTests.model(opened)
    var screens = ParamSet(schema: EmissionScreensProcess.schema)
    try screens.set("haOpacity", .number(0.6))
    try model.apply(StretchProcess.id, params: ParamSet(schema: StretchProcess.schema))
    try model.apply(EmissionScreensProcess.id, params: screens)
    #expect(model.staleFrom == nil)
    let before = model.steps

    try model.applyBranch("Ha", DenoiseProcess.id, params: BranchTests.denoise())

    // The combination reads RGB only (its defaults), the stretch the head: the screens are the
    // first step that read the Hα layer.
    #expect(model.staleFrom == 2)
    #expect(model.steps == before, "nothing re-applied by itself (R2)")
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    let workspace = try StudioWorkspaceModel(studio: model, base: [.color, .emission])
    try await StudioUndo.replayMain(workspace, on: undoManager)

    #expect(model.staleFrom == nil)
    #expect(model.steps.map(\.processID) == before.map(\.processID))
    #expect(model.steps.map(\.params) == before.map(\.params), "the recorded values")
    #expect(model.steps[2].file != before[2].file, "the screens ran again")
    #expect(Array(model.steps[..<2]) == Array(before[..<2]), "the steps before it kept")
    let haHead = try #require(model.session.branches.branch("Ha")?.history.steps.last?.file)
    #expect(model.steps[2].branchHeads == ["Ha": haHead])
    let replayed = model.head.planes

    undoManager.undo()
    #expect(model.steps.count == 2, "one ⌘Z takes the replay back")
    undoManager.redo()
    #expect(model.head.planes == replayed)
  }

  @Test(
    "a replay that would reach a host-tool step refuses before anything moves", .scratchDirectory)
  func testReplayRefusesHostToolStepFirst() async throws {
    let opened = try BranchTests.project()
    defer { try? opened.package.close() }
    let model = try BranchTests.model(opened)
    try Self.finish(model)
    try model.apply("stars-split", params: ParamSet(schema: ParamSchema([])), result: model.head)
    try model.applyBranch("Ha", DenoiseProcess.id, params: BranchTests.denoise())
    let before = model.steps
    #expect(model.staleFrom == 2)

    await #expect(throws: PipelineError.toolMissing("stars-split")) {
      try await model.replayMain()
    }
    #expect(model.steps == before, "nothing undone")
    #expect(model.staleFrom == 2)
  }
}
