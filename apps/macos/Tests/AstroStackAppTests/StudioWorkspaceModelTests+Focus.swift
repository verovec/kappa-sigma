import AstroStackApp
import Foundation
import ProcessKit
import RenderKit
import SwiftUI
import TestSupport
import Testing

extension StudioWorkspaceModelTests {
  @Test(
    "focus hides the columns and restores them; head, panel and history are untouched",
    .scratchDirectory, arguments: [true, false])
  func testFocus_HidesAndRestores(panelShown: Bool) async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.workspace(opened, bundle: StudioModelTests.bundle())
    // Not through `showsPanel`: the test never writes the user's own choice.
    workspace.viewer.model.showPanel(panelShown, remembered: false)
    workspace.choose(StretchProcess.id)
    workspace.panel?.set("targetBackground", .number(0.2))
    await workspace.previewNow()
    let (head, values, steps) = (
      workspace.studio.head, workspace.panel?.params, workspace.studio.steps
    )

    workspace.toggleFocus()
    #expect(workspace.isFocused)
    #expect(!workspace.viewer.model.showsPanel)
    workspace.toggleFocus()
    #expect(!workspace.isFocused)
    #expect(workspace.viewer.model.showsPanel == panelShown)
    #expect(workspace.studio.head === head)
    #expect(workspace.panel?.params == values)
    #expect(workspace.studio.steps == steps)
  }

  @Test(
    "the journey sidebar is hidden while focused, then back as the user left it",
    arguments: [
      (NavigationSplitViewVisibility.all, false, NavigationSplitViewVisibility.all),
      (.all, true, .detailOnly), (.detailOnly, false, .detailOnly), (.automatic, true, .detailOnly),
    ])
  func testFocus_SidebarVisibility(
    stored: NavigationSplitViewVisibility, focused: Bool, shown: NavigationSplitViewVisibility
  ) {
    #expect(ProjectWindowView.sidebar(stored: stored, focused: focused) == shown)
  }
}
