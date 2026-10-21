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
        WelcomeView(model: model, actions: Self.noActions), language)
      host.layoutSubtreeIfNeeded()
      await model.reload()
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
      tools: model)
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

  @Test("File › New Project… opens the welcome window with its naming sheet up")
  func testNewProjectRaisesNamingSheet() {
    WelcomeWindow.model.isNaming = false
    AppDelegate().newProject(nil)
    defer {
      WelcomeWindow.model.isNaming = false
      WelcomeWindow.show().close()
    }
    #expect(WelcomeWindow.isVisible)
    #expect(WelcomeWindow.model.isNaming)
  }

  @Test("a project window, however it was opened, dismisses the welcome window")
  func testProjectWindowDismissesWelcome() throws {
    WelcomeWindow.show()
    let document = try ProjectDocument(type: ProjectPackage.typeIdentifier)
    defer { document.close() }

    document.makeWindowControllers()

    #expect(!WelcomeWindow.isVisible)
  }

  @Test("a tool its card has since found reads as usable; one still missing does not")
  func testUsableAfterCardRecheck() {
    let missing = WelcomeModel.ToolRow(tool: .graxpert, status: .missing(path: "/g"))
    let url = URL(fileURLWithPath: "/Applications/GraXpert.app")

    #expect(ToolStrip.usable(missing, card: .found(url)) == .found(path: url.path, version: nil))
    #expect(ToolStrip.usable(missing, card: .missing) == nil)
    #expect(ToolStrip.usable(missing, card: nil) == nil)
  }

  @Test("a too old Siril says so with the sentence the app shows for Siril errors")
  func testTooOldReusesSirilSentence() {
    let row = WelcomeModel.ToolRow(tool: .siril, status: .tooOld(path: "/s", version: "1.2.6"))
    #expect(
      ToolStrip.reason(row).text("fr")
        == UserFacingError.siril(.tooOld(version: "1.2.6")).message.text("fr"))
  }

  @Test("a project window closing the welcome window also drops its naming sheet")
  func testDismissDropsNamingSheet() {
    WelcomeWindow.showNewProject()

    WelcomeWindow.dismiss()

    #expect(!WelcomeWindow.model.isNaming)
    #expect(!WelcomeWindow.isVisible)
  }

  @Test(
    "the naming sheet lays out with and without an error, in each language",
    arguments: ["en", "fr"])
  func testNamingSheetLaysOut(_ language: String) {
    let model = WelcomeModel(recentURLs: { [] }, tools: Self.mixedTools)
    for error in [nil, UserFacingError.projectName] {
      let sheet = NewProjectSheet(
        model: model, actions: Self.noActions, target: "M 31", error: error)
      let host = LocalisedScreensTests.host(sheet, language)
      host.layoutSubtreeIfNeeded()
      #expect(host.fittingSize.width >= 380)
    }
  }

  @Test("Create makes the project, lowers the sheet and opens it")
  func testSubmitCreatesAndOpens() {
    let model = WelcomeModel(recentURLs: { [] }, tools: Self.mixedTools)
    model.isNaming = true
    var opened: [URL] = []
    let made = URL(fileURLWithPath: "/Projects/M 31.astrostack")
    let actions = WelcomeView.Actions(
      open: { opened.append($0) }, choose: {}, create: { _ in made })

    #expect(NewProjectSheet.submit("M 31", model: model, actions: actions) == nil)
    #expect(opened == [made])
    #expect(!model.isNaming)
  }

  @Test("a refused name keeps the sheet up with the reason, and opens nothing")
  func testSubmitRefusal() {
    let model = WelcomeModel(recentURLs: { [] }, tools: Self.mixedTools)
    model.isNaming = true
    var opened: [URL] = []
    let actions = WelcomeView.Actions(
      open: { opened.append($0) }, choose: {}, create: { _ in throw UserFacingError.projectName })

    #expect(NewProjectSheet.submit("   ", model: model, actions: actions) == .projectName)
    #expect(opened.isEmpty)
    #expect(model.isNaming)
  }

  @Test("a project open in a document is counted by that document, by its resolved path")
  func testOpenProjectsCountsOpenDocuments() throws {
    let document = try ProjectDocument(type: ProjectPackage.typeIdentifier)
    let url = try #require(document.packageURL)
    NSDocumentController.shared.addDocument(document)
    defer { document.close() }

    let open = WelcomeWindow.openProjects()

    #expect(open[WelcomeModel.key(url)] == .some(document.projectSummary()))
  }

  @Test("a recent project that cannot be opened is reported, not swallowed", .scratchDirectory)
  func testOpenFailureIsReported() async throws {
    let url = try ScratchDirectory.url.appendingPathComponent("Gone.astrostack")
    var failures: [any Error] = []

    await WelcomeWindow.open(url) { failures.append($0) }

    #expect(failures.count == 1)
  }
}
