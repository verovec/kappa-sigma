import AstroStackApp
import Foundation
import ImageKit
import ProcessKit
import TestSupport
import Testing

/// Card 0159: a click on an applied step opens it with its recorded values (`editStep`), the
/// preview draws its chain (0158); Cancel leaves everything as it was, Apply revises it (0157).
extension StudioWorkspaceModelTests {
  /// The studio with stretch, curves applied after the combination, then a background
  /// extraction recorded as a host-tool step.
  static func edited(_ opened: StudioModelTests.Opened) throws -> StudioWorkspaceModel {
    let studio = try StudioModelTests.model(opened)
    try studio.apply(StretchProcess.id, params: try StudioModelTests.stretch(target: 0.2))
    try studio.apply(CurvesProcess.id, params: ParamSet(schema: CurvesProcess.schema))
    try studio.apply(
      BackgroundExtractionProcess.id, params: ParamSet(schema: BackgroundExtractionProcess.schema),
      result: studio.head)
    return try StudioWorkspaceModel(studio: studio, base: [.color])
  }

  @Test(
    "testEditStep_OpensRecordedParams: first, middle and host-tool steps", .scratchDirectory,
    arguments: [0, 1, 3])
  func testEditStep_OpensRecordedParams(_ index: Int) throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.edited(opened)
    let step = workspace.studio.steps[index]

    workspace.editStep(index)

    let panel = try #require(workspace.panel)
    #expect(panel.type.id == step.processID && panel.params == step.params)
    #expect(workspace.editing == index && workspace.editedStep == index)
    #expect(workspace.failure == nil)
  }

  @Test("testCancelEdit_LeavesHistoryAndHead", .scratchDirectory)
  func testCancelEdit_LeavesHistoryAndHead() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.edited(opened)
    let (steps, head) = (workspace.studio.steps, workspace.studio.head.planes)
    workspace.editStep(1)
    try #require(workspace.panel).set("targetBackground", .number(0.4))
    await workspace.settlePreview()

    workspace.cancelEdit()

    #expect(workspace.editing == nil && workspace.panel == nil && !workspace.isPreviewing)
    #expect(workspace.studio.steps == steps && workspace.studio.head.planes == head)
    #expect(workspace.viewer.model.image.planes == head, "the viewer is back on the head")
  }

  @Test("testApplyEdit_RevisesAndClearsEditing", .scratchDirectory)
  func testApplyEdit_RevisesAndClearsEditing() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.edited(opened)
    let undoManager = StudioUndoRunTests.undoManager()
    let before = workspace.studio.steps
    workspace.editStep(1)
    let revised = try StudioModelTests.stretch(target: 0.4)
    try #require(workspace.panel).set("targetBackground", .number(0.4))

    await StudioUndo.applyEdit(workspace, on: undoManager)

    #expect(workspace.failure == nil)
    #expect(workspace.editing == nil && workspace.panel == nil)
    #expect(workspace.studio.steps[1].params == revised)
    #expect(workspace.studio.steps.count == 3, "the host-tool step waits for ▶ Run")
    #expect(workspace.studio.session.history.versions.last?.steps == Array(before[1...]))
    #expect(undoManager.undoActionName == String(localized: .app("Revise Step")))
  }

  @Test("testEditStep_OnBranch: refused with its reason", .scratchDirectory)
  func testEditStep_OnBranch() throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.workspace(opened, bundle: BranchTests.bundle())
    try workspace.studio.apply(StretchProcess.id, params: ParamSet(schema: StretchProcess.schema))
    workspace.select(.branch("Ha"))

    workspace.editStep(1)

    #expect(workspace.editing == nil)
    #expect(
      workspace.failure.map { String(localized: $0) }
        == String(localized: .app("Only the combined image's steps can be edited: show it first.")))
  }

  @Test("testEditStep_RefusedWhileRunning: refused with its reason", .scratchDirectory)
  func testEditStep_RefusedWhileRunning() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let during = BackgroundProcessTests.During()
    let workspace = try BackgroundProcessTests.workspace(
      opened, tool: BackgroundProcessTests.tool(during: during))
    try workspace.studio.apply(StretchProcess.id, params: ParamSet(schema: StretchProcess.schema))
    let refused = Recorded<String?>()
    during.set {
      workspace.editStep(1)
      refused.append(workspace.failure.map { String(localized: $0) })
    }
    workspace.choose(BackgroundExtractionProcess.id)
    let done = Recorded<Bool>()

    workspace.startTool { done.append($0) }
    while done.all.isEmpty { await Task.yield() }

    let reason = String(
      localized: .app("A run, a replay or a tool is moving the image: wait for it, then edit."))
    #expect(refused.all == [reason] && workspace.editing == nil)
  }

  /// A one-plane mask over the head of `studio`, letting its left half through.
  static func halfMask(_ studio: StudioModel) -> AstroImage {
    let head = studio.head
    let plane = (0..<(head.width * head.height)).map {
      Float($0 % head.width < head.width / 2 ? 1 : 0)
    }
    return AstroImage(
      width: head.width, height: head.height, planes: [plane], metadata: head.metadata)
  }

  /// The processes of the applied steps, as a column that follows the history plans them.
  static func planned(_ studio: StudioModel) -> [String] {
    studio.steps.map(\.processID)
  }

  @Test("testEditSummary_CountsReplayAndTool", .scratchDirectory)
  func testEditSummary_CountsReplayAndTool() throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.edited(opened)

    workspace.editStep(1)

    #expect(workspace.editReplayed == 1 && workspace.editStop == 3)
    let words = { (language: String) in
      workspace.editSummary(locale: Locale(identifier: language)).map { String(localized: $0) }
    }
    #expect(
      words("fr") == [
        "Rejoue 1 étape suivante",
        "S’arrête avant Extraction de fond (étape 4) : ▶ Lancer l’applique, puis la suite",
      ])
    #expect(words("en").first == "Replays 1 later step")
    #expect(
      workspace.editTitle(locale: Locale(identifier: "fr")).map { String(localized: $0) }
        == "Étape 2 · Étirement — modification")
    #expect(!workspace.isRecomputed(1) && workspace.isRecomputed(2) && workspace.isRecomputed(3))
  }

  @Test("testMaskedStep_NoWarningWhenRecorded: the recorded mask is the edit's", .scratchDirectory)
  func testMaskedStep_NoWarningWhenRecorded() throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let studio = try StudioModelTests.model(opened)
    try studio.apply(StretchProcess.id, params: try StudioModelTests.stretch(target: 0.2))
    try studio.apply(
      SaturationProcess.id, params: ParamSet(schema: SaturationProcess.schema),
      mask: Self.halfMask(studio))
    let workspace = try StudioWorkspaceModel(studio: studio, base: [.color])

    workspace.editStep(2)
    #expect(workspace.editUsesRecordedMask)
    workspace.editStep(1)
    #expect(!workspace.editUsesRecordedMask)
  }

  @Test(
    "after a revise stopped before a host tool, ▶ Run keeps the pending steps' masks",
    .scratchDirectory)
  func testPendingMasks_AfterReviseBeforeTool() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let studio = try StudioModelTests.model(opened)
    try studio.apply(StretchProcess.id, params: try StudioModelTests.stretch(target: 0.2))
    try studio.apply(
      BackgroundExtractionProcess.id, params: ParamSet(schema: BackgroundExtractionProcess.schema),
      result: studio.head)
    let mask = Self.halfMask(studio)
    try studio.apply(
      SaturationProcess.id, params: ParamSet(schema: SaturationProcess.schema), mask: mask)
    #expect(
      try studio.pendingMasks(from: 2, planned: Self.planned(studio)).isEmpty,
      "no revise left anything pending")

    let planned = Self.planned(studio)
    try await studio.reviseStep(1, params: try StudioModelTests.stretch(target: 0.4))

    #expect(studio.steps.count == 2)
    let pending = try studio.pendingMasks(from: 2, planned: planned)
    #expect(pending.keys.sorted() == [3] && pending[3]?.planes == mask.planes)
    var diverging = planned
    diverging[3] = CurvesProcess.id
    #expect(
      try studio.pendingMasks(from: 2, planned: diverging).isEmpty,
      "a column planning another process there gets no mask")
  }

  @Test(
    "testVersionsMenu_RestoreAndDrop: compare, an undoable restore, drop frees the files",
    .scratchDirectory)
  func testVersionsMenu_RestoreAndDrop() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.edited(opened)
    let undoManager = StudioUndoRunTests.undoManager()
    let before = workspace.studio.steps
    workspace.editStep(1)
    try #require(workspace.panel).set("targetBackground", .number(0.4))
    await StudioUndo.applyEdit(workspace, on: undoManager)
    let revised = workspace.studio.steps
    let version = try #require(workspace.versions.last)
    #expect(workspace.bytes(ofVersion: version.id) > 0)

    workspace.toggleCompare(version: version.id)
    #expect(workspace.comparingVersion == version.id && workspace.viewer.reference != nil)

    undoManager.undo()
    #expect(workspace.comparingVersion == nil, "a ⌘Z ends a version's compare")
    undoManager.redo()
    let current = try #require(workspace.versions.last)
    StudioUndo.restoreVersion(workspace, current.id, on: undoManager)
    #expect(workspace.studio.steps == before && workspace.failure == nil)
    #expect(workspace.comparingVersion == nil, "the compare ends with the move")
    #expect(undoManager.undoActionName == String(localized: .app("Restore Version")))
    undoManager.undo()
    #expect(workspace.studio.steps == revised, "⌘Z puts the revised chain back")

    let kept = try #require(workspace.versions.last)
    let directory = workspace.studio.session.history.directory
    let files = kept.steps.map { directory.appendingPathComponent($0.file).path }
    StudioUndo.dropVersion(workspace, kept.id, on: undoManager)

    #expect(workspace.versions.isEmpty)
    #expect(!undoManager.canUndo, "no ⌘Z left to swap the dropped version back")
    #expect(files.allSatisfy { !FileManager.default.fileExists(atPath: $0) })
    #expect(workspace.studio.steps == revised)
  }

  @Test("a step with no panel (StarNet's) is refused with its reason", .scratchDirectory)
  func testEditStep_NoPanelRefused() throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let studio = try StudioModelTests.model(opened)
    try studio.apply(
      StarSeparation.id, params: ParamSet(schema: StarSeparation.schema), result: studio.head,
      outputs: [.starless: studio.head])
    let workspace = try StudioWorkspaceModel(studio: studio, base: [.color])

    workspace.editStep(1)

    #expect(workspace.editing == nil && workspace.panel == nil)
    #expect(workspace.failure != nil)
  }
}
