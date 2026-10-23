import AstroStackApp
import Foundation
import ProcessKit
import Testing

/// The viewer shows the head once the history moved, the panel left open: an Apply is never
/// shown twice, an Undo never hidden under the same values previewed again, and nothing is
/// recorded that was not on screen (R2).
extension StudioWorkspaceModelTests {
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
}
