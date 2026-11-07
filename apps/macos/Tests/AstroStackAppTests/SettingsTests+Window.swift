import AppKit
import AstroStackApp
import Foundation
import SwiftUI
import Testing

extension SettingsTests {
  /// Card 0177: the window was a title bar only — a grouped `Form` has no intrinsic height and the
  /// fixed-size window never got a content size.
  @Test("testSettingsWindow_hasContentHeight: the real window shows its content (card 0177)")
  func testSettingsWindow_hasContentHeight() throws {
    let window = SettingsWindow.show()
    defer { window.close() }
    try #require(window.contentView).layoutSubtreeIfNeeded()
    let content = window.contentRect(forFrameRect: window.frame).size
    #expect(content.height >= 400, "\(content)")
    #expect(content.width >= 460, "\(content)")
  }
}

extension SettingsTests {
  /// Card 0177: « S3 connections… » in Import and Export opens the window on its tab; ⌘, keeps the
  /// last one.
  @Test("testSettingsWindow_showsAskedTab", arguments: SettingsTab.allCases)
  func testSettingsWindow_showsAskedTab(_ tab: SettingsTab) {
    let window = SettingsWindow.show(tab: tab)
    defer { window.close() }
    #expect(SettingsWindow.selection.tab == tab)
    #expect(SettingsWindow.show() === window)
    #expect(SettingsWindow.selection.tab == tab, "no tab asked: the last one stays")
  }

  /// The window is at least as wide as what its tabs lay out, in each language, on each tab.
  @Test(
    "testSettingsTab_laysOut: each tab hosted alone fits the window (card 0177)",
    arguments: SettingsTab.allCases, ["en", "fr"])
  func testSettingsTab_laysOut(_ tab: SettingsTab, _ language: String) throws {
    let name = "fr.astrostack.tests.settings.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let view = SettingsView(
      setting: LanguageSetting(defaults: defaults, domain: name), relaunch: {},
      tools: WelcomeModel(recentURLs: { [] }, tools: WelcomeViewTests.mixedTools),
      selection: SettingsSelection(tab))
    let host = NSHostingView(rootView: view.environment(\.locale, Locale(identifier: language)))
    host.layoutSubtreeIfNeeded()
    let size = host.fittingSize
    #expect(size.width >= SettingsTab.formWidth && size.height >= SettingsTab.formMinHeight)
    #expect(size.width <= SettingsWindow.contentSize.width, "\(tab) \(language): \(size)")
    #expect(size.height <= SettingsWindow.contentSize.height, "\(tab) \(language): \(size)")
  }
}

extension SettingsTests {
  /// Review of card 0177: a selection naming a tab the view does not show left the tab view blank.
  @Test(
    "a selection without its tab shows General",
    arguments: [
      (SettingsTab.tools, [SettingsTab.general, .folders, .s3, .storage], SettingsTab.general),
      (.tools, SettingsTab.allCases, .tools), (.s3, [.general, .s3], .s3),
    ])
  func testShownTab(_ tab: SettingsTab, _ tabs: [SettingsTab], _ shown: SettingsTab) {
    #expect(SettingsView.shown(tab, in: tabs) == shown)
  }
}
