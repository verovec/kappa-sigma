import AstroStackApp
import Foundation
import ProcessKit
import TestSupport
import Testing

/// Row notes (card 0135): the panel says, under a row, why its value cannot run on this stack;
/// they follow the values and the head, and the process itself is never greyed for them.
extension StudioWorkspaceModelTests {
  @Test("testRowNotesFollowTheHead", .scratchDirectory)
  func testRowNotesFollowTheHead() async throws {
    let opened = try BranchTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.workspace(opened, bundle: BranchTests.bundle())  // RGB, Ha, OIII
    workspace.choose(EmissionScreensProcess.id)
    let panel = try #require(workspace.panel)
    #expect(panel.layerIDs == ["RGB", "Ha", "OIII"])
    #expect(panel.rowNotes.isEmpty, "Hα and OIII are in the stack")
    #expect(!panel.visibleSpecs.contains { $0.id.hasPrefix("sii") })

    // Asking for SII on a stack without it: the rows appear with their note; the catalogue's
    // verdict on the process (roles, never values) does not move.
    let greyed = {
      workspace.catalogue.flatMap(\.entries).first { $0.id == EmissionScreensProcess.id }?
        .unavailable
    }
    let before = greyed()
    panel.set("siiEnabled", .flag(true))
    #expect(panel.rowNotes["siiEnabled"]?.subject == "[SII]")
    #expect(panel.visibleSpecs.contains { $0.id == "siiEnabled" })
    #expect(greyed() == before)

    panel.set("siiEnabled", .flag(false))
    #expect(panel.rowNotes.isEmpty)
    #expect(!panel.visibleSpecs.contains { $0.id.hasPrefix("sii") })

    // The head moves (an Apply): the panel's layers and notes are read again from the session.
    panel.layerIDs = ["RGB"]
    await workspace.previewNow()
    try workspace.apply()
    #expect(workspace.panel === panel && panel.layerIDs == ["RGB", "Ha", "OIII"])
  }

  @Test("the row note is worded in the view's language, with its subject")
  func testRowNoteWords() {
    let note = RowNote(reason: "the screen needs its line layer", subject: "[SII]")
    let english = ProcessPanelModel.words(
      reason: note.reason, subject: note.subject, locale: Locale(identifier: "en"))
    let french = ProcessPanelModel.words(
      reason: note.reason, subject: note.subject, locale: Locale(identifier: "fr"))
    #expect(english.contains("SII") && french.contains("SII") && english != french)
  }

  @Test(
    "testRowNotesOnOpen: a broadband-only stack opens the screens with the lines' notes",
    .scratchDirectory)
  func testRowNotesOnOpen() throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.workspace(opened, bundle: StudioModelTests.bundle())  // RGB only
    workspace.choose(EmissionScreensProcess.id)
    let panel = try #require(workspace.panel)
    #expect(panel.layerIDs == ["RGB"])
    // Hα and OIII are on by default: their rows stay, each with its note; SII hides.
    #expect(panel.rowNotes["haEnabled"]?.subject == "Hα")
    #expect(panel.rowNotes["oiiiEnabled"]?.subject == "[OIII]")
    #expect(panel.rowNotes["siiEnabled"] == nil)
    #expect(panel.visibleSpecs.contains { $0.id == "haOpacity" })
    #expect(!panel.visibleSpecs.contains { $0.id.hasPrefix("sii") })
  }
}
