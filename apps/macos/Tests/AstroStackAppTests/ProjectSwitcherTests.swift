import AstroStackApp
import Foundation
import ProjectKit
import TestSupport
import Testing

/// The project switcher (card 0146): the catalog's projects in three sections, the current one
/// checked, then Open… / New project… / Welcome window; every choice a closure the window wires.
@MainActor
@Suite("ProjectSwitcher — other projects one click away from the project window")
struct ProjectSwitcherTests {
  nonisolated static func url(_ name: String) -> URL {
    URL(fileURLWithPath: "/tmp/switcher/\(name).astrostack")
  }

  nonisolated static func entry(_ name: String, _ origin: ProjectCatalog.Origin)
    -> ProjectCatalog.Entry
  {
    ProjectCatalog.Entry(url: url(name), target: name, summary: nil, origin: origin)
  }

  struct Row: CustomTestStringConvertible, Sendable {
    let name: String
    let entries: [ProjectCatalog.Entry]
    let current: URL?
    let open: [String]
    let recent: [String]
    let folder: [String]
    let checked: String?
    var testDescription: String { name }
  }

  nonisolated static let rows: [Row] = [
    Row(
      name: "open first, recents, then the folder; the current window checked",
      entries: [
        entry("M31", .open), entry("IC1848", .open), entry("M45", .recent),
        entry("NGC7000", .folder),
      ],
      current: url("M31"), open: ["M31", "IC1848"], recent: ["M45"], folder: ["NGC7000"],
      checked: "M31"),
    Row(
      name: "an untitled window checks nothing", entries: [entry("M45", .recent)], current: nil,
      open: [], recent: ["M45"], folder: [], checked: nil),
    Row(
      name: "an empty catalog", entries: [], current: url("M31"), open: [], recent: [], folder: [],
      checked: nil),
  ]

  @Test("testItems_fromCatalog", arguments: rows)
  func testItems_fromCatalog(row: Row) {
    let items = ProjectSwitcher.Items.make(entries: row.entries)
    #expect(items.open.map(\.target) == row.open)
    #expect(items.recent.map(\.target) == row.recent)
    #expect(items.folder.map(\.target) == row.folder)
    // The window checks the entry whose key is its own, as the menu does.
    let currentKey = row.current.map(WelcomeModel.key)
    let all = items.open + items.recent + items.folder
    #expect(all.first { $0.key == currentKey }?.target == row.checked)
    #expect(all.allSatisfy { $0.key == WelcomeModel.key($0.url) })
  }

  @Test(
    "the model's head names a saved project; an untitled one shows no UUID and checks nothing",
    .scratchDirectory)
  func testHead_untitledShowsNoTarget() throws {
    let project = try ProjectPackage.create(
      at: ScratchDirectory.url.appendingPathComponent("M31.astrostack"))
    defer { try? project.close() }
    let saved = ProjectWindowModel(
      store: { project.store }, folder: { project.url }, planning: { _ in ImportPlanningStub.empty }
    )
    #expect(saved.head == ProjectWindowModel.Head(target: "M31", current: project.url))
    #expect(saved.head.key == WelcomeModel.key(project.url))
    let untitled = ProjectWindowModel(
      store: { project.store }, folder: { project.url },
      services: { _ in ImportServices(planning: ImportPlanningStub.empty) }, isSaved: { false })
    #expect(untitled.head == ProjectWindowModel.Head(target: "", current: nil))
  }

  @Test("the live source reads the welcome window's catalog; the empty one lists nothing")
  func testSources() {
    #expect(ProjectSwitcher.Source.live.catalog === WelcomeWindow.model.catalog)
    #expect(ProjectSwitcher.Source.empty.catalog.entries.isEmpty)
    #expect(
      ProjectSwitcher.Items.make(entries: ProjectSwitcher.Source.empty.catalog.entries).open.isEmpty
    )
  }
}
