import AstroStackApp
import Foundation
import ProjectKit
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
      name: "a project listed twice keeps its first section",
      entries: [entry("M31", .open), entry("M31", .recent), entry("M31", .folder)],
      current: nil, open: ["M31"], recent: [], folder: [], checked: nil),
    Row(
      name: "an untitled window checks nothing", entries: [entry("M45", .recent)], current: nil,
      open: [], recent: ["M45"], folder: [], checked: nil),
    Row(
      name: "an empty catalog", entries: [], current: url("M31"), open: [], recent: [], folder: [],
      checked: nil),
  ]

  @Test("testItems_fromCatalog", arguments: rows)
  func testItems_fromCatalog(row: Row) {
    let items = ProjectSwitcher.Items.make(entries: row.entries, current: row.current)
    #expect(items.open.map(\.target) == row.open)
    #expect(items.recent.map(\.target) == row.recent)
    #expect(items.folder.map(\.target) == row.folder)
    let all = items.open + items.recent + items.folder
    #expect(Set(all.map(\.url)).count == all.count, "no duplicate across sections")
    #expect(all.first { $0.isCurrent }?.target == row.checked)
  }

  @Test("testActions: a project calls open(url); the fixed items call their closure, nothing else")
  func testActions() {
    var log: [String] = []
    let actions = ProjectSwitcher.Actions(
      open: { log.append("open \($0.lastPathComponent)") },
      choose: { log.append("choose") },
      newProject: { log.append("new") },
      welcome: { log.append("welcome") })
    actions.perform(.project(Self.url("M45")))
    actions.perform(.open)
    actions.perform(.newProject)
    actions.perform(.welcome)
    #expect(log == ["open M45.astrostack", "choose", "new", "welcome"])
  }
}
