import AstroStackApp
import Foundation
import ProcessKit
import Testing

/// The viewer shows the head once the history moved, the panel left open: an Apply is never
/// shown twice, an Undo never hidden under the same values previewed again, and nothing is
/// recorded that was not on screen (R2).
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
    #expect(!workspace.isPreviewing)
    #expect(workspace.viewer.model.image.planes == workspace.studio.head.planes)
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
}

extension PipelineSidebarModelTests {
  @Test("one ⌘Z takes a whole pipeline run back, one ⇧⌘Z runs it again", .scratchDirectory)
  func testRun_IsUndoneAtOnce() async throws {
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

  @Test("a run's ⌘Z does nothing once the history moved past its last step", .scratchDirectory)
  func testRun_Undo_ChecksTheHead() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let (workspace, sidebar) = try Self.sidebar(opened, try Self.fourSteps())
    let undoManager = StudioWorkspaceModelTests.undoManager()
    undoManager.beginUndoGrouping()
    await sidebar.run(undoManager: undoManager)
    undoManager.endUndoGrouping()
    try workspace.undo()  // the history's own button
    undoManager.undo()
    #expect(workspace.studio.steps.count == 3, "never part of a run")
  }
}
