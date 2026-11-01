import AstroStackApp
import Foundation
import ProcessKit
import Testing

/// Card 0159: a done step of the pipeline column opens in the Studio with its recorded values;
/// a step not applied, or one the history holds under another process, opens nothing.
extension PipelineSidebarModelTests {
  @Test(
    "a done row edits its history step; a pending or diverging row opens nothing",
    .scratchDirectory)
  func testEditStep_FromDoneRow() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let (workspace, sidebar) = try Self.sidebar(opened, try Self.fourSteps(stop: true))
    await sidebar.run()
    #expect(workspace.studio.steps.count == 2, "halted before curves")

    #expect(!sidebar.editStep(2) && workspace.editing == nil, "not applied yet")
    #expect(sidebar.editStep(1))
    #expect(workspace.editing == 1 && workspace.panel?.type.id == StretchProcess.id)
    #expect(workspace.panel?.params == workspace.studio.steps[1].params)

    var diverging = try Self.fourSteps()
    diverging.steps.swapAt(1, 2)
    sidebar.show(diverging)
    workspace.cancelEdit()
    #expect(!sidebar.editStep(1) && workspace.editing == nil, "the column diverged there")
  }
}
