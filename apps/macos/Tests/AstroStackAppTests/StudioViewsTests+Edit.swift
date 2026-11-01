import AppKit
import AstroStackApp
import Foundation
import HelpKit
import ProcessKit
import RenderKit
import SwiftUI
import Testing

/// Card 0159: the side column of an edit — its header, Cancel / Apply change instead of Close /
/// Apply, each history row's eye, the Versions menu — with an identifier per control; the
/// re-edit help card and the « version » term in fr and en.
extension StudioViewsTests {
  @Test("an edit shows its own buttons, each row its eye, the Versions menu", .scratchDirectory)
  func testSideColumn_Edit() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try StudioWorkspaceModelTests.edited(opened)
    let undoManager = StudioUndoRunTests.undoManager()
    workspace.editStep(1)
    try #require(workspace.panel).set("targetBackground", .number(0.4))
    await StudioUndo.applyEdit(workspace, on: undoManager)
    workspace.editStep(1)
    await workspace.settlePreview()

    let entries = AccessibilityAuditTests.entries(StudioSideView(model: workspace))
    let ids = Set(entries.map(\.id))

    for id in ["edit.cancel", "edit.apply", "step.1.compare", "versions", "step.0"] {
      #expect(ids.contains("fr.astrostack.stage.studio." + id), "\(id)")
    }
    #expect(!ids.contains("fr.astrostack.stage.studio.apply"), "the head's Apply is hidden")
    #expect(AccessibilityAudit.problems(entries) == [])
    let host = NSHostingView(rootView: StudioSideView(model: workspace).frame(width: 320))
    host.frame = NSRect(x: 0, y: 0, width: 320, height: 900)
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.height > 0)
  }

  @Test("the re-edit help card and the « version » term exist in fr and en")
  func testReEditHelp() {
    #expect(AppGlossary.help.coverageProblems(stages: ["re-edit"]).isEmpty)
    #expect(AppGlossary.termIDs.contains("studio.version"))
    for language in ["fr", "en"] {
      #expect(
        StageHelp.help(card: "re-edit", locale: Locale(identifier: language)) != nil, "\(language)")
      #expect(
        AppGlossary.label("studio.version", locale: Locale(identifier: language)) == "Version")
    }
  }
}
