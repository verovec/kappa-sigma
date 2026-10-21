import AppKit
import AstroStackApp
import Foundation
import ProjectKit
import StackKit
import SwiftUI
import TestSupport
import Testing

@MainActor
@Suite("Welcome window: recent projects, a named new project, the host tools, in fr and en")
struct WelcomeViewTests {
  /// Siril found, GraXpert missing, StarNet too old: every row kind at once.
  static let mixedTools = HostTools { tool in
    switch tool {
    case .siril: .found(path: "/Applications/Siril.app", version: "1.4.4")
    case .graxpert: .missing(path: "/Applications/GraXpert.app")
    case .starnet: .tooOld(path: "/usr/local/bin/starnet2", version: "1.0")
    }
  }

  static let noActions = WelcomeView.Actions(
    open: { _ in }, choose: {}, create: { _ in URL(fileURLWithPath: "/") })

  @Test(
    "the window lays out with and without recent projects and tools, in each language",
    .scratchDirectory, arguments: ["en", "fr"])
  func testLaysOutInEveryVariant(_ language: String) async throws {
    let project = try NewProject.create(target: "M 31", in: try ScratchDirectory.url)
    for urls in [[], [project]] {
      let model = WelcomeModel(recentURLs: { urls }, tools: Self.mixedTools)
      let host = LocalisedScreensTests.host(
        WelcomeView(model: model, hostTools: Self.mixedTools, actions: Self.noActions), language)
      host.layoutSubtreeIfNeeded()
      model.reload()
      await model.recheckTools()
      host.layoutSubtreeIfNeeded()
      #expect(host.fittingSize.width >= 520)
      #expect(model.recent.count == urls.count)
    }
  }

  @Test("a recent project shows its counts, or that it cannot be read", arguments: ["en", "fr"])
  func testCounts(_ language: String) {
    let counts = WelcomeView.counts(ProjectSummary(sources: 2, stacks: 1, images: 0))
    #expect(counts.text(language).contains("2"))
    #expect(counts.text(language).contains("1"))
    #expect(WelcomeView.counts(nil).text(language) != counts.text(language))
  }

  @Test(
    "a usable tool shows its version and path; an unusable one says why",
    arguments: ["en", "fr"])
  func testToolWords(_ language: String) {
    let found = ToolStrip.found(.found(path: "/siril", version: "1.4.4")).text(language)
    #expect(found.contains("1.4.4") && found.contains("/siril"))
    #expect(ToolStrip.found(.found(path: "/g.app", version: nil)).text(language).contains("/g.app"))
    let old = ToolStrip.reason(.init(tool: .siril, status: .tooOld(path: "/s", version: "1.2.6")))
    #expect(old.text(language).contains("1.2.6"))
    let reasons = HostTool.allCases.map {
      ToolStrip.reason(.init(tool: $0, status: .missing(path: "/x"))).text(language)
    }
    #expect(Set(reasons).count == HostTool.allCases.count)
  }

  @Test("an install card's re-check reports the tool's path only once it is usable")
  func testLocator() async {
    #expect(await ToolStrip.locator(.siril, Self.mixedTools)()?.path == "/Applications/Siril.app")
    #expect(await ToolStrip.locator(.graxpert, Self.mixedTools)() == nil)
    #expect(await ToolStrip.locator(.starnet, Self.mixedTools)() == nil)
  }

  @Test("each tool links to where the user installs it; nothing is downloaded for them")
  func testInstallURLs() {
    #expect(HostTool.allCases.allSatisfy { $0.installURL.scheme == "https" })
  }

  @Test("Settings lays out its Tools section in each language", arguments: ["en", "fr"])
  func testSettingsTools(_ language: String) async throws {
    let name = "fr.astrostack.tests.settings.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let model = WelcomeModel(recentURLs: { [] }, tools: Self.mixedTools)
    await model.recheckTools()
    let view = SettingsView(
      setting: LanguageSetting(defaults: defaults, domain: name), relaunch: {},
      tools: (model, Self.mixedTools))
    let host = LocalisedScreensTests.host(view, language)
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.width >= 460)
  }

  @Test("Window › Welcome Window shows one window, titled from the catalog, reused")
  func testOneWelcomeWindow() {
    AppDelegate().showWelcome(nil)
    let window = WelcomeWindow.show()
    defer { window.close() }
    #expect(WelcomeWindow.show() === window)
    #expect(WelcomeWindow.isVisible)
    #expect(window.title == String(localized: .app("Welcome to AstroStack")))
  }
}
