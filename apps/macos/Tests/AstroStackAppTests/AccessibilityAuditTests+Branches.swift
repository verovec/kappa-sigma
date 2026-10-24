import AppKit
import AstroStackApp
import Foundation
import ProcessKit
import RenderKit
import SwiftUI
import TestSupport
import Testing

extension AccessibilityAuditTests {
  @Test(
    "the Studio's channel switcher and stale banner: labelled, identified (card 0119)",
    .scratchDirectory, arguments: ["en", "fr"])
  func testBranchWorkspace(language: String) async throws {
    let opened = try BranchTests.project()
    defer { try? opened.package.close() }
    let workspace = try StudioWorkspaceModelTests.workspace(opened, bundle: BranchTests.bundle())
    try StudioModelBranchTests.finish(workspace.studio)
    try workspace.studio.applyBranch("Ha", DenoiseProcess.id, params: BranchTests.denoise())

    let switcher = Self.entries(StudioChannelSwitcher(model: workspace), language: language)
    let side = Self.entries(StudioSideView(model: workspace), language: language)

    #expect(AccessibilityAudit.problems(switcher + side) == [])
    let ids = Set((switcher + side).map(\.id))
    for key in ["main", "RGB", "Ha", "OIII"] {
      #expect(ids.contains("fr.astrostack.stage.studio.channel." + key))
    }
    #expect(ids.contains("fr.astrostack.stage.studio.compare-with"))
    #expect(ids.contains("fr.astrostack.stage.studio.replay-stale"), "the banner on Combined")
    #expect(ids.contains("fr.astrostack.help.stage.branches"))
  }
}
