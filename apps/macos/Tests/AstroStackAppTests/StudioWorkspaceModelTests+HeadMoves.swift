import AstroStackApp
import Foundation
import ProcessKit
import Testing

/// The viewer shows the head once the history moved, the panel left open: an Apply is never
/// shown twice, an Undo never hidden under the same values previewed again; ⌘Z takes a pipeline
/// run back.
extension StudioWorkspaceModelTests {
  /// An undo manager driven by explicit groups, as a test needs it.
  static func undoManager() -> UndoManager {
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    return undoManager
  }

  @Test(
    "after Apply and Undo the panel stays open on the head, not on its values again",
    .scratchDirectory)
  func testHeadChanged_ShowsTheHead() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.workspace(opened, bundle: StudioModelTests.bundle())
    let combined = workspace.viewer.model.image.planes
    workspace.choose(StretchProcess.id)
    await workspace.previewNow()

    try workspace.apply()
    await workspace.settlePreview()
    #expect(!workspace.isPreviewing && workspace.panel != nil)
    #expect(workspace.viewer.model.image.planes == workspace.studio.head.planes, "applied once")

    try workspace.undo()
    await workspace.settlePreview()
    #expect(!workspace.isPreviewing)
    #expect(workspace.viewer.model.image.planes == combined, "the undo is seen")

    try #require(workspace.panel).set("targetBackground", .number(0.2))
    await workspace.settlePreview()
    #expect(workspace.isPreviewing, "a value moved previews again")
  }
}

extension PipelineSidebarModelTests {
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
}
