import AppKit
import AstroStackApp
import Foundation
import SwiftUI
import TestSupport
import Testing

/// AstroStack › Settings…: one window, the language picker laid out in both languages.
@MainActor
@Suite("Settings — the language window")
struct SettingsTests {
  @Test("relaunch waits for this instance to be gone, then opens the one instance (card 0147)")
  func testRelaunchScript() {
    let script = SettingsWindow.relaunchScript(pid: 4242)
    #expect(script.contains("kill -0 4242"), "a probe of the pid, never a signal")
    #expect(script.contains("open \"$1\""), "the bundle path is a positional, never interpolated")
    #expect(script.contains("seq 1 75"), "15 s at most: a cancelled quit never relaunches later")
    #expect(script.contains("AstroStack-relaunch.log"), "what open says is kept")
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

  @Test(
    "testAstroFolderSection: the chosen root with ~, one line per subfolder, lays out (card 0148)",
    .scratchDirectory, arguments: ["en", "fr"])
  func testAstroFolderSection(_ language: String) throws {
    let name = "fr.astrostack.tests.settings.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let root = try ScratchDirectory.url.appendingPathComponent("astro")
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("captures"), withIntermediateDirectories: true)
    let astro = AstroFolderSetting(defaults: defaults, home: URL(fileURLWithPath: "/Users/x"))
    #expect(astro.choose(root))
    #expect(!astro.choose(root.appendingPathComponent("missing")), "a refused pick keeps the root")
    let home = URL(fileURLWithPath: NSHomeDirectory())
    #expect(
      SettingsView.astroPath(home.appendingPathComponent("Documents/astro")) == "~/Documents/astro")
    #expect(SettingsView.astroLines(astro).map(\.found) == [true, false, false, false, false])
    let view = SettingsView(
      setting: LanguageSetting(defaults: defaults, domain: name), relaunch: {}, astro: astro)
    let host = NSHostingView(rootView: view.environment(\.locale, Locale(identifier: language)))
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.width >= 460)
    #expect(host.fittingSize.height > 0)
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
