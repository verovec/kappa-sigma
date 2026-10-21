import AppKit
import AstroStackApp
import Foundation
import ProjectKit
import StackKit
import StringCatalog
import SwiftUI
import TestSupport
import Testing

/// The Import sheet and the project window laid out offscreen in every state the plan can put
/// them in: empty, scanning, failed, a plan with a colour light, gaps, an exclusion, warnings.
@MainActor
@Suite("ImportSheet and ProjectWindowView — every state lays out")
struct ImportSheetTests {
  static func host<Content: View>(_ view: Content) -> NSHostingView<Content> {
    let host = NSHostingView(rootView: view)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1000, height: 800), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    return host
  }

  @Test("empty, then a full plan with overrides, gaps and an exclusion, then a failure")
  func testSheetStates() async throws {
    let planner = ImportViewModelTests.FakePlanner()
    let model = ImportViewModel(planning: planner.planning)
    var added: [ImportRequest] = []
    let host = Self.host(ImportSheet(model: model, onAdd: { added.append($0) }, onCancel: {}))
    let empty = host.fittingSize

    model.choose(folder: URL(fileURLWithPath: "/c/M31-DB"))
    await model.settled()
    let plan = try #require(model.plan)
    let rows = plan.nights.flatMap(\.sets)
    model.setFilterSet(.dualband, for: rows[0])
    model.mapFilter("Ha", to: "ignore")
    model.exclude(rows[1])
    let cell = try #require(model.plan?.calibration.first?.cells.last)
    model.setIncluded(false, cell)
    await model.settled()
    host.layoutSubtreeIfNeeded()
    #expect(model.plan?.calibration.first?.hasGap == true, "no dark nor flat in the fake capture")
    #expect(host.fittingSize.height > empty.height, "the plan fills the sheet")

    planner.failure = InspectError.noFolders
    model.rescan()
    await model.settled()
    host.layoutSubtreeIfNeeded()
    #expect(model.error != nil)
    #expect(added.isEmpty)
  }

  @Test("the project window lists its sources once a capture is added", .scratchDirectory)
  func testProjectWindowStates() throws {
    let project = try ProjectPackage.create(
      at: ScratchDirectory.url.appendingPathComponent("P.astrostack"))
    defer { try? project.close() }
    let window = ProjectWindowModel(
      store: { project.store }, planning: { _ in ImportPlanningStub.empty })
    let host = Self.host(ProjectWindowView(model: window))
    window.startImport()
    host.layoutSubtreeIfNeeded()
    window.add(ImportRequest(paths: ["/c/M31-DB"]))
    host.layoutSubtreeIfNeeded()
    #expect(window.sources.count == 1)
    #expect(host.fittingSize.width >= 640)
  }

  @Test("the sheet lays out in every state in each language", arguments: ["en", "fr"])
  func testSheetLaysOutInLanguage(_ language: String) async throws {
    let planner = ImportViewModelTests.FakePlanner()
    let model = ImportViewModel(planning: planner.planning)
    let host = Self.host(
      ImportSheet(model: model, onAdd: { _ in }, onCancel: {}, addError: .projectClosed)
        .environment(\.locale, Locale(identifier: language)))
    model.choose(folder: URL(fileURLWithPath: "/c/M31-DB"))
    await model.settled()
    let rows = try #require(model.plan).nights.flatMap(\.sets)
    model.exclude(rows[1])
    await model.settled()
    host.layoutSubtreeIfNeeded()
    planner.failure = InspectError.unreadableFolder("/c/M31-DB")
    model.rescan()
    await model.settled()
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.width >= 820)
  }

  @Test(
    "a view shows the app catalog's text in its locale",
    arguments: zip(
      ["en", "fr"], ["Empty project", "Projet vide"]))
  func testViewsResolveTheirLocale(language: String, expected: String) {
    let locale = Locale(identifier: language)
    let resolved = Self.host(Text(.app("Empty project")).fixedSize().environment(\.locale, locale))
    let verbatim = Self.host(Text(verbatim: expected).fixedSize().environment(\.locale, locale))
    #expect(resolved.fittingSize == verbatim.fittingSize)
  }

  /// The screens migrated by card 0073; ImportFormat's units wait for AstroFormat (0074).
  static let migrated = [
    "ProjectWindowView", "ProjectWindowModel", "ImportSheet", "ImportInventoryView",
    "ImportOverridesView", "ImportCalibrationView", "SettingsView", "MasterInspectView",
    "MasterInspectViewModel", "MasterFormat", "LegacyRunView", "LegacyRunModel",
    "UserFacingError", "ProjectFacts", "StageStatus", "JourneyState", "JourneySidebar",
    "StagePane", "DataStagePane", "StackingStagePane", "StudioStagePane", "RunPanel",
    "RunOutcomeView", "RunSummary", "RunViewModel", "LayerList", "LayerDetail", "JournalView",
    "PreviewThumbnail", "KnobPanel", "KnobRow", "KnobPanelViewModel",
  ]

  @Test("the project window and import sheet carry no English literal outside the catalog")
  func testNoEnglishLiteralOutsideTheCatalog() throws {
    let root = try ModuleBoundary.packageRoot(from: #filePath) + "/Sources/AstroStackApp/"
    let catalog = try StringCatalog(
      contentsOf: URL(fileURLWithPath: root + "Localizable.xcstrings"))
    for file in Self.migrated {
      let source = try String(contentsOfFile: root + file + ".swift", encoding: .utf8)
      #expect(CatalogAudit.uncatalogued(in: source, file: file, catalog: catalog) == [])
    }
  }
}
