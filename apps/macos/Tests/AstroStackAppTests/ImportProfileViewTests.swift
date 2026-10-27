import AppKit
import AstroStackApp
import FilterKit
import Foundation
import ProcessKit
import StackKit
import SwiftUI
import Testing

/// The Import sheet's profile box (card 0060) lays out in each state — proposed, undecided, a pick,
/// none, rejected copies listed — in French and English; Help opens its windows once.
@MainActor
@Suite("Import profile box and Help windows — every state lays out")
struct ImportProfileViewTests {
  static func host(_ model: ImportViewModel, language: String) -> NSSize {
    let host = NSHostingView(
      rootView: ImportProfileView(model: model)
        .environment(\.locale, Locale(identifier: language)).frame(width: 640))
    host.layoutSubtreeIfNeeded()
    return host.fittingSize
  }

  @Test("proposed, undecided, a pick, none and rejected copies lay out", arguments: ["en", "fr"])
  func testStatesLayOut(language: String) async throws {
    let proposed = await ImportProfileTests.model()
    #expect(Self.host(proposed, language: language).height > 60)

    let undecided = ImportViewModel(
      planning: ImportViewModel.reporting { request in
        ImportPlan(
          inventory: ProfileInputsTests.inventory([
            ProfileInputsTests.LightSet("Sh2-129", Filter.color, true, .unknown)
          ]), library: [], request: request)
      }, rejectedProfiles: ["broken": "not a profile"])
    undecided.choose(folder: URL(fileURLWithPath: "/c/Sh2-129"))
    await undecided.settled()
    #expect(ImportProfileView.tag(for: undecided) == ImportProfileView.undecided)
    #expect(Self.host(undecided, language: language).height > 40)

    proposed.chooseProfile(.profile("nebula-mono-narrowband"))
    #expect(Self.host(proposed, language: language).height > 60)
    proposed.chooseProfile(.none)
    #expect(ImportProfileView.tag(for: proposed) == "")
    #expect(Self.host(proposed, language: language).height > 40)
  }

  @Test("a value line reads process and parameter titles in the language, numbers in its notation")
  func testValueLine() throws {
    let galaxy = try #require(
      ImportViewModel.shippedProfiles.first { $0.id == "galaxy-osc-broadband-dualband" })
    let screens = try #require(galaxy.steps.first { $0.recipe.processID == "emission-screens" })
    let french = ImportProfileView.line(
      screens, "haBlack", registry: try ProcessRegistry.standard(), locale: Locale(identifier: "fr")
    )
    #expect(french.contains("0,115"))
    #expect(!french.contains("emission-screens"), "the process title, not its id: \(french)")
  }

  @Test("Help › Keyboard Shortcuts and Glossary open one window each, reused")
  func testHelpWindows() {
    let delegate = AppDelegate()
    delegate.showShortcuts(nil)
    delegate.showGlossary(nil)
    let shortcuts = UtilityWindow.show("shortcuts", title: .app("Keyboard Shortcuts")) {
      ShortcutsSheet()
    }
    let glossary = UtilityWindow.show("glossary", title: .app("Glossary")) { GlossaryView() }
    defer {
      shortcuts.close()
      glossary.close()
    }
    #expect(shortcuts !== glossary)
    #expect(
      UtilityWindow.show("shortcuts", title: .app("Keyboard Shortcuts")) { ShortcutsSheet() }
        === shortcuts)
    #expect(shortcuts.title == String(localized: .app("Keyboard Shortcuts")))
  }
}
