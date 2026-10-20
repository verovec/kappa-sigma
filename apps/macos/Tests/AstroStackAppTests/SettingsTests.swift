import AppKit
import AstroStackApp
import Foundation
import SwiftUI
import Testing

/// AstroStack › Settings…: one window, the language picker laid out in both languages.
@MainActor
@Suite("Settings — the language window")
struct SettingsTests {
  @Test("the settings lay out in each language", arguments: ["en", "fr"])
  func testSettingsLayOut(_ language: String) throws {
    let name = "fr.astrostack.tests.settings.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    var relaunched = false
    let view = SettingsView(
      setting: LanguageSetting(defaults: defaults, domain: name), relaunch: { relaunched = true }
    )
    let host = NSHostingView(rootView: view.environment(\.locale, Locale(identifier: language)))
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.width >= 460)
    #expect(!relaunched, "nothing relaunches until the user asks")
  }

  @Test("Settings… shows one window, titled from the catalog, reused")
  func testOneSettingsWindow() {
    AppDelegate().showSettings(nil)
    let window = SettingsWindow.show()
    defer { window.close() }
    #expect(SettingsWindow.show() === window)
    #expect(window.title == String(localized: .app("Settings")))
    #expect(window.isReleasedWhenClosed == false)
  }
}
