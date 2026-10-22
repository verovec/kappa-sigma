import AstroStackApp
import Foundation
import ProcessKit
import Testing

extension StudioWorkspaceModelTests {
  /// Closing the panel shows the head again; a compare toggles; a failed preview, compare or
  /// history move is said in the panel, and the viewer never keeps an older preview.
  @Test("close, toggle compare, and every failure said in the panel", .scratchDirectory)
  func testCloseCompareFailures() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.workspace(opened, bundle: StudioModelTests.bundle())
    let combined = workspace.viewer.model.image.planes

    workspace.choose(StretchProcess.id)
    await workspace.previewNow()
    #expect(workspace.isPreviewing)
    workspace.closePanel()
    #expect(workspace.panel == nil && !workspace.isPreviewing)
    #expect(workspace.viewer.model.image.planes == combined)

    workspace.toggleCompare(0)
    #expect(workspace.comparing == 0)
    workspace.toggleCompare(0)
    #expect(workspace.comparing == nil && workspace.failure == nil)
    workspace.toggleCompare(7)
    #expect(workspace.comparing == nil && workspace.failure != nil, "no step 7")

    #expect(throws: HistoryError.nothingToRedo) { try workspace.redo() }
    #expect(workspace.failure != nil)
    #expect(workspace.viewer.model.image.planes == combined)

    // A preview that cannot run (no starless layer) shows the head again, and says why.
    workspace.choose(StretchProcess.id)
    await workspace.previewNow()
    #expect(workspace.isPreviewing && workspace.failure != nil, "a redo failure stays in view")
    workspace.choose(StarRecompositionProcess.id)
    await workspace.previewNow()
    #expect(!workspace.isPreviewing && workspace.failure != nil)
    #expect(workspace.viewer.model.image.planes == combined)
  }
}
