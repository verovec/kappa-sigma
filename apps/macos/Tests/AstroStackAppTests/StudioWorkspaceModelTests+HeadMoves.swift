import AstroStackApp
import Foundation
import ProcessKit
import Testing

/// The viewer shows the head once the history moved, the panel left open: an Apply is never
/// shown twice, an Undo never hidden under the same values previewed again, and nothing is
/// recorded that was not on screen (R2); ⌘Z, the history's buttons and a pipeline run share one
/// undo stack.
extension StudioWorkspaceModelTests {
  /// An undo manager driven by explicit groups, as a test needs it.
  static func undoManager() -> UndoManager {
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    return undoManager
  }

  /// The workspace with the stretch applied once, its panel still open.
  static func stretched(_ opened: StudioModelTests.Opened) async throws -> StudioWorkspaceModel {
    let workspace = try Self.workspace(opened, bundle: StudioModelTests.bundle())
    workspace.choose(StretchProcess.id)
    await workspace.previewNow()
    try workspace.apply()
    return workspace
  }

  @Test(
    "after Apply the head is shown once, the panel open and its preview suspended",
    .scratchDirectory)
  func testHeadChanged_Apply_ShowsTheHeadOnce() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try await Self.stretched(opened)
    await workspace.settlePreview()
    #expect(!workspace.isPreviewing && workspace.isPreviewSuspended && workspace.panel != nil)
    #expect(workspace.viewer.model.image.planes == workspace.studio.head.planes)
  }

  @Test("after Undo the step is seen gone, not drawn back by the panel", .scratchDirectory)
  func testHeadChanged_Undo_IsSeen() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try await Self.stretched(opened)
    try workspace.undo()
    await workspace.settlePreview()
    #expect(!workspace.isPreviewing && workspace.isPreviewSuspended && workspace.panel != nil)
    #expect(workspace.viewer.model.image.planes == workspace.studio.head.planes)
  }

  @Test("a refused history move keeps the panel's values on screen", .scratchDirectory)
  func testHeadChanged_RefusedMove_PreviewsAgain() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.workspace(opened, bundle: StudioModelTests.bundle())
    workspace.choose(StretchProcess.id)
    await workspace.previewNow()
    #expect(throws: HistoryError.nothingToRedo) { try workspace.redo() }
    await workspace.settlePreview()
    #expect(workspace.isPreviewing && !workspace.isPreviewSuspended)
  }

  @Test(
    "on a new head Apply shows the values first and records on the next Apply", .scratchDirectory)
  func testSuspendedPreview_ApplyShowsFirst() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try await Self.stretched(opened)
    try workspace.apply()
    #expect(workspace.studio.steps.count == 2, "nothing recorded unseen")
    #expect(workspace.isPreviewing && !workspace.isPreviewSuspended)
    let shown = workspace.viewer.model.image.planes
    try workspace.apply()
    #expect(workspace.studio.steps.count == 3 && workspace.studio.head.planes == shown)
  }

  @Test("a refused move leaves a suspended panel suspended", .scratchDirectory)
  func testSuspendedPreview_RefusedMove_StaysSuspended() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try await Self.stretched(opened)
    #expect(throws: HistoryError.nothingToRedo) { try workspace.redo() }
    await workspace.settlePreview()
    #expect(workspace.isPreviewSuspended && !workspace.isPreviewing)
  }

  @Test("an Apply pressed while suspended previews, whatever value it commits", .scratchDirectory)
  func testSuspendedPreview_RecordedApplyPreviews() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try await Self.stretched(opened)
    let undoManager = UndoManager()
    StudioUndo.apply(workspace, undoManager: undoManager)
    #expect(workspace.studio.steps.count == 2 && workspace.isPreviewing)
  }

  @Test("a value moved, or Preview, shows the panel's values again", .scratchDirectory)
  func testSuspendedPreview_Resumes() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try await Self.stretched(opened)
    workspace.resumePreview()
    #expect(workspace.isPreviewing && !workspace.isPreviewSuspended)
    try workspace.undo()
    try #require(workspace.panel).set("targetBackground", .number(0.2))
    await workspace.settlePreview()
    #expect(workspace.isPreviewing && !workspace.isPreviewSuspended)
  }

  @Test("the history's buttons take ⌘Z's stack: ⌘Z goes on from where they left", .scratchDirectory)
  func testHistoryButtons_ShareTheUndoStack() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.workspace(opened, bundle: StudioModelTests.bundle())
    let undoManager = Self.undoManager()
    for process in [StretchProcess.id, CurvesProcess.id] {
      workspace.choose(process)
      await workspace.previewNow()
      undoManager.beginUndoGrouping()
      StudioUndo.apply(workspace, undoManager: undoManager)
      undoManager.endUndoGrouping()
    }

    StudioUndo.undo(workspace, undoManager: undoManager)
    #expect(workspace.studio.steps.map(\.processID) == ["channel-combination", "stretch"])
    undoManager.undo()
    #expect(workspace.studio.steps.map(\.processID) == ["channel-combination"], "⌘Z goes on")
    StudioUndo.redo(workspace, undoManager: undoManager)
    undoManager.redo()
    #expect(
      workspace.studio.steps.map(\.processID) == ["channel-combination", "stretch", "curves"])
  }

  @Test("a stale ⌘Z entry never swallows the history's Undo button", .scratchDirectory)
  func testHistoryButtons_StaleEntry_StillUndo() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.workspace(opened, bundle: StudioModelTests.bundle())
    let undoManager = Self.undoManager()
    workspace.choose(StretchProcess.id)
    await workspace.previewNow()
    undoManager.beginUndoGrouping()
    StudioUndo.apply(workspace, undoManager: undoManager)
    undoManager.endUndoGrouping()
    // The head moves without ⌘Z: the Studio entry on top now names a step that is gone.
    try workspace.undo()
    workspace.choose(CurvesProcess.id)
    await workspace.previewNow()
    try workspace.apply()
    #expect(workspace.studio.steps.map(\.processID) == ["channel-combination", "curves"])

    StudioUndo.undo(workspace, undoManager: undoManager)
    #expect(workspace.studio.steps.map(\.processID) == ["channel-combination"])
  }
}

extension PipelineSidebarModelTests {
  @Test("at a breakpoint on a new head, Continue shows the values first", .scratchDirectory)
  func testContinue_SuspendedPreview_ShowsFirst() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let (workspace, sidebar) = try Self.sidebar(opened, try Self.fourSteps(stop: true))
    await sidebar.run()
    try workspace.undo()
    try workspace.redo()
    #expect(workspace.isPreviewSuspended && sidebar.canContinue)

    await sidebar.continueRun()
    #expect(workspace.studio.steps.count == 2, "nothing applied unseen")
    #expect(workspace.isPreviewing && !workspace.isPreviewSuspended)
    await sidebar.continueRun()
    #expect(workspace.studio.steps.count == 4)
  }

  @Test("⌘Z takes a pipeline run back, ⇧⌘Z runs its steps again", .scratchDirectory)
  func testRun_IsUndoable() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let (workspace, sidebar) = try Self.sidebar(opened, try Self.fourSteps())
    let undoManager = StudioWorkspaceModelTests.undoManager()
    undoManager.beginUndoGrouping()
    await sidebar.run(undoManager: undoManager)
    undoManager.endUndoGrouping()
    let done = workspace.studio.steps.map(\.processID)
    #expect(done == ["channel-combination", "stretch", "curves", "saturation"])

    undoManager.undo()
    #expect(workspace.studio.steps.map(\.processID) == ["channel-combination"])
    undoManager.redo()
    #expect(workspace.studio.steps.map(\.processID) == done)
  }

  @Test("a run ended after its workspace was retired registers no ⌘Z", .scratchDirectory)
  func testRun_RetiredWorkspace_RegistersNothing() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let (workspace, sidebar) = try Self.sidebar(opened, try Self.fourSteps())
    await sidebar.run()
    let undoManager = StudioWorkspaceModelTests.undoManager()
    workspace.retire()
    undoManager.beginUndoGrouping()
    StudioUndo.recordRun(workspace, from: 1, on: undoManager)
    undoManager.endUndoGrouping()
    #expect(undoManager.undoActionName.isEmpty, "no Studio Step on the stack")
  }
}
