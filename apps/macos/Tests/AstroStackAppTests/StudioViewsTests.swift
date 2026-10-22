import AppKit
import AstroStackApp
import Foundation
import Metal
import ProcessKit
import RenderKit
import SwiftUI
import TestSupport
import Testing

/// The Studio's views laid out on a real workspace (card 0087): the side column with a panel,
/// its mask values and the history; the catalogue rows, greyed with their reason; the whole
/// workspace. Each control reports its identifier.
@MainActor
@Suite(
  "Studio views — side column, mask row, catalogue rows, workspace",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
struct StudioViewsTests {
  @Test(
    "the side column shows the panel, each mask source's values, the history", .scratchDirectory)
  func testSideColumn() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try StudioWorkspaceModelTests.workspace(
      opened, bundle: StudioModelTests.bundle())
    let empty = Set(AccessibilityAuditTests.entries(StudioSideView(model: workspace)).map(\.id))
    #expect(empty.contains("fr.astrostack.stage.studio.undo"))

    workspace.choose(StretchProcess.id)
    await workspace.previewNow()
    try workspace.apply()
    for mask in [
      Mask(source: .luminosityRange(low: 0.2, high: 1, softness: 0.1)),
      Mask(source: .stars(threshold: 0.02, radiusPx: 8), inverted: true),
    ] {
      workspace.mask = mask
      let ids = Set(AccessibilityAuditTests.entries(StudioSideView(model: workspace)).map(\.id))
      #expect(ids.contains("fr.astrostack.stage.studio.apply"))
      #expect(ids.contains("fr.astrostack.stage.studio.mask.source"))
      #expect(ids.contains("fr.astrostack.parameter.studio.mask.feather.slider"))
      #expect(ids.contains("fr.astrostack.stage.studio.step.1"))
    }
    let entries = AccessibilityAuditTests.entries(StudioSideView(model: workspace))
    #expect(AccessibilityAudit.problems(entries) == [])
  }

  @Test("a catalogue row reports its process and shows why it is greyed", .scratchDirectory)
  func testCatalogueRows() throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try StudioWorkspaceModelTests.workspace(
      opened, bundle: StudioModelTests.bundle())
    for entry in workspace.catalogue.flatMap(\.entries) {
      let ids = AccessibilityAuditTests.entries(StudioCatalogueRow(entry: entry, model: workspace))
        .map(\.id)
      #expect(ids == ["fr.astrostack.stage.studio.process.\(entry.id)"])
    }
    let host = NSHostingView(
      rootView: StudioWorkspaceView(model: workspace).frame(
        width: 1200, height: 700))
    host.frame = NSRect(x: 0, y: 0, width: 1200, height: 700)
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.width > 0)
  }

  @Test("every Studio and history failure has its sentence in fr and en")
  func testStudioErrorSentences() {
    let errors: [any Error] = [
      StudioError.unknownProcess("x"), StudioError.emptyBundle, HistoryError.noStep(2),
      HistoryError.nothingToUndo, HistoryError.nothingToRedo, HistoryError.unknownSnapshot("v1"),
      HistoryError.duplicateSnapshot("v1"), HistoryError.unreadable("bad"),
    ]
    for error in errors {
      for language in ["fr", "en"] {
        var message = UserFacingError(error).message
        message.locale = Locale(identifier: language)
        let text = String(localized: message)
        #expect(!text.isEmpty && !text.contains("unknownProcess"), "\(error) \(language)")
      }
    }
  }
}
