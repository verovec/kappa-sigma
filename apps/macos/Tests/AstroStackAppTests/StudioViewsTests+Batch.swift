import AppKit
import AstroStackApp
import Foundation
import ProcessKit
import RenderKit
import StackKit
import SwiftUI
import TestSupport
import Testing

extension StudioViewsTests {
  /// Card 0092: a batch process's side column — the engine picker with GraXpert greyed, its
  /// install card, Apply, and once applied the « Show the background model » toggle; every
  /// control labelled and identified.
  @Test("the side column of a batch process: picker, install card, model toggle", .scratchDirectory)
  func testBatchSideColumn() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try BackgroundProcessTests.workspace(
      opened, tools: BackgroundProcessTests.tools(missing: [.graxpert]))
    workspace.choose(BackgroundExtractionProcess.id)
    await workspace.refreshTools()
    var ids = Set(AccessibilityAuditTests.entries(StudioSideView(model: workspace)).map(\.id))
    #expect(ids.contains("fr.astrostack.parameter.background-extraction.engine.choice"))
    #expect(ids.contains("fr.astrostack.stage.studio.apply"))
    #expect(ids.contains("fr.astrostack.stage.studio.showModel"))
    #expect(!ids.contains("fr.astrostack.stage.studio.mask.source"), "no mask on a host tool")

    try #require(workspace.panel).set("engine", .choice("siril-rbf"))
    await workspace.runBatch()
    try workspace.toggleModel()
    let entries = AccessibilityAuditTests.entries(StudioSideView(model: workspace))
    ids = Set(entries.map(\.id))
    #expect(ids.contains("fr.astrostack.stage.studio.showModel"))
    #expect(AccessibilityAudit.problems(entries) == [])
  }
}
