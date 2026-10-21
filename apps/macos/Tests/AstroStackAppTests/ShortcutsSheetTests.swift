import AppKit
import AstroStackApp
import SwiftUI
import Foundation
import Testing

/// Help › Keyboard Shortcuts (card 0079): every catalog command, grouped by journey stage, found
/// by its title in the interface language.
@Suite("Shortcuts sheet — every catalog command, grouped by stage, searchable, fr and en")
struct ShortcutsSheetTests {
  @Test("lists every catalog command once, app-wide first, then by stage", arguments: ["en", "fr"])
  func testListsEveryCatalogCommand(language: String) {
    let locale = Locale(identifier: language)
    let groups = ShortcutsSheet.groups(matching: "", locale: locale)
    let listed = groups.flatMap(\.rows).map(\.id)
    #expect(listed.sorted() == CommandCatalog.commands.filter(\.isBuilt).map(\.id).sorted())
    #expect(Set(listed).count == listed.count)
    #expect(groups.first?.stage == nil, "app-wide commands first")
    let stages = groups.compactMap(\.stage)
    #expect(stages == JourneyStage.allCases.filter(stages.contains), "stages in working order")
    let save = groups.flatMap(\.rows).first { $0.id == "file.save" }
    #expect(save?.title == (language == "fr" ? "Enregistrer" : "Save"))
    #expect(save?.shortcut == "⌘S")
    #expect(groups.flatMap(\.rows).first { $0.id == "viewer.compare" }?.shortcut == "⌥")
  }

  @Test(
    "the search keeps the commands whose title or shortcut matches, case and accents aside",
    arguments: zip(
      ["enregistrer", "ENREG", "⌘S", "zzz", "reference"],
      [
        ["file.save", "file.saveAs"], ["file.save", "file.saveAs"], ["file.save"], [],
        ["viewer.compare"],
      ]))
  func testSearch(query: String, ids: [String]) {
    let found = ShortcutsSheet.groups(matching: query, locale: Locale(identifier: "fr"))
      .flatMap(\.rows).map(\.id)
    #expect(found == ids)
  }

  @Test("the glossary lists every term once, sorted, and its search reads definitions too")
  func testGlossarySearch() {
    let french = Locale(identifier: "fr")
    let all = GlossaryView.terms(matching: "", locale: french).map(\.term)
    #expect(all.count == Set(AppGlossary.termIDs).count)
    #expect(
      all.map(\.label) == all.map(\.label).sorted { $0.localizedCompare($1) == .orderedAscending })
    #expect(
      GlossaryView.terms(matching: "donnees", locale: french).contains { $0.id == "stage.data" })
    #expect(GlossaryView.terms(matching: "zzzz", locale: french).isEmpty)
  }

  @MainActor
  @Test("the shortcuts and glossary windows lay out in both languages", arguments: ["en", "fr"])
  func testWindowsLayOut(language: String) {
    for view in [AnyView(ShortcutsSheet()), AnyView(GlossaryView())] {
      let host = NSHostingView(
        rootView: view.environment(\.locale, Locale(identifier: language)))
      host.layoutSubtreeIfNeeded()
      #expect(host.fittingSize.width >= 420 && host.fittingSize.height >= 480)
    }
  }

  @Test("a group is titled with the stage's glossary term, app-wide commands as General")
  func testGroupTitles() {
    let groups = ShortcutsSheet.groups(matching: "", locale: Locale(identifier: "fr"))
    #expect(groups.first?.title == "Général")
    #expect(groups.first { $0.stage == .studio }?.title == "Studio")
  }
}
