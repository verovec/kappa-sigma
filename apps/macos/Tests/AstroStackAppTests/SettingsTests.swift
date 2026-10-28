import AppKit
import AstroStackApp
import Foundation
import SwiftUI
import Testing

/// AstroStack › Settings…: one window, the language picker laid out in both languages.
@MainActor
@Suite("Settings — the language window")
struct SettingsTests {
  @Test("relaunch waits for this instance to be gone, then opens the one instance (card 0147)")
  func testRelaunchScript() {
    let script = SettingsWindow.relaunchScript(pid: 4242, bundle: "/Apps/Astro Stack.app")
    #expect(script.contains("kill -0 4242"), "a probe of the pid, never a signal")
    #expect(script.contains("open \"/Apps/Astro Stack.app\""))
    #expect(!script.contains("open -n") && !script.contains("-9") && !script.contains("TERM"))
    #expect(script.hasSuffix("&"), "the subshell outlives this process")
  }

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
