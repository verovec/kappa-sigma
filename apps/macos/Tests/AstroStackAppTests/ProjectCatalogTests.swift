import AstroStackApp
import Foundation
import ProjectKit
import TestSupport
import Testing

/// Every project the app can find (card 0145): the open ones, AppKit's recents and the projects
/// folder, merged into one list — nothing on disk goes unseen because it fell off the recents.
@MainActor
@Suite("ProjectCatalog: open, recent and projects-folder projects in one list")
struct ProjectCatalogTests {
  /// One row: which of the packages are open, recent (in that order) and in the folder.
  struct Case: CustomTestStringConvertible, Sendable {
    let name: String
    var open: [String] = []
    var recent: [String] = []
    var folder: [String] = []
    let expected: [(String, ProjectCatalog.Origin)]
    var testDescription: String { name }
  }

  nonisolated static let cases = [
    Case(
      name: "each origin alone", open: ["M 31"], recent: ["IC 1848"], folder: ["NGC 7000"],
      expected: [("M 31", .open), ("IC 1848", .recent), ("NGC 7000", .folder)]),
    Case(
      name: "a project in two origins is listed once, under the first",
      open: ["M 31"], recent: ["M 31", "IC 1848"], folder: ["IC 1848", "M 31", "M 45"],
      expected: [("M 31", .open), ("IC 1848", .recent), ("M 45", .folder)]),
    Case(
      name: "recents keep AppKit's order; the folder's rest goes by target name",
      recent: ["NGC 7000", "M 31"], folder: ["M 45", "IC 1848", "M 31", "M 101"],
      expected: [
        ("NGC 7000", .recent), ("M 31", .recent), ("IC 1848", .folder), ("M 45", .folder),
        ("M 101", .folder),
      ]),
    Case(
      name: "a deleted recent is dropped", recent: ["Gone", "M 31"],
      expected: [("M 31", .recent)]),
    Case(name: "nothing anywhere", expected: []),
  ]

  /// `names` as packages in `folder`; "Gone" is never created.
  static func packages(_ names: [String], in folder: URL) throws -> [URL] {
    try names.map { name in
      let url = folder.appendingPathComponent(name).appendingPathExtension("astrostack")
      if name != "Gone", !FileManager.default.fileExists(atPath: url.path) {
        try ProjectPackage.create(at: url).close()
      }
      return url
    }
  }

  @Test("open, recent and folder projects merge into one list", .scratchDirectory, arguments: cases)
  func testReload_mergesThreeOrigins(_ row: Case) async throws {
    let folder = try ScratchDirectory.url
    let open = try Self.packages(row.open, in: folder)
    let recent = try Self.packages(row.recent, in: folder)
    let inFolder = try Self.packages(row.folder, in: folder)
    let catalog = ProjectCatalog(
      openProjects: { open.map { ($0, ProjectSummary()) } }, recentURLs: { recent },
      folderURLs: { inFolder })

    await catalog.reload()

    #expect(catalog.entries.map(\.target) == row.expected.map(\.0))
    #expect(catalog.entries.map(\.origin) == row.expected.map(\.1))
  }

  @Test(
    "an open project's counts come from its document, never re-read from disk",
    .scratchDirectory)
  func testReload_countsFromDocumentWhenOpen() async throws {
    // Not SQLite: reading it from disk would give no counts. Moved from WelcomeModelTests.
    let open = try ScratchDirectory.url.appendingPathComponent("M 31.astrostack")
    try FileManager.default.createDirectory(at: open, withIntermediateDirectories: true)
    try Data("not sqlite".utf8).write(to: open.appendingPathComponent("project.db"))
    let counted = ProjectSummary(sources: 3, stacks: 1)
    let catalog = ProjectCatalog(
      openProjects: { [(open, counted)] }, recentURLs: { [open.appendingPathComponent("")] },
      folderURLs: { [open] })

    await catalog.reload()

    #expect(catalog.entries.map(\.summary) == [counted])
    #expect(catalog.entries.map(\.origin) == [.open])
  }

  @Test("a folder project read from disk has its counts, an unreadable one none", .scratchDirectory)
  func testReload_readsFolderProjects() async throws {
    let folder = try ScratchDirectory.url
    let m31 = try NewProject.create(target: "M 31", in: folder)
    let package = try ProjectPackage.open(at: m31)
    _ = try package.store.addSource(kind: .night, path: "/captures/M31/2026-09-22")
    try package.close()
    let broken = folder.appendingPathComponent("Broken.astrostack")
    try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
    try Data("not sqlite".utf8).write(to: broken.appendingPathComponent("project.db"))
    let catalog = ProjectCatalog(
      openProjects: { [] }, recentURLs: { [] }, folderURLs: { [m31, broken] })

    await catalog.reload()

    #expect(catalog.entries.map(\.target) == ["Broken", "M 31"])
    #expect(catalog.entries.map(\.summary?.sources) == [nil, 1])
  }

  @Test(
    "the folder listing holds only project packages; a missing folder lists nothing",
    .scratchDirectory)
  func testFolderListing_packagesOnly() throws {
    let folder = try ScratchDirectory.url
    let m31 = try NewProject.create(target: "M 31", in: folder)
    try FileManager.default.createDirectory(
      at: folder.appendingPathComponent("captures"), withIntermediateDirectories: true)
    try Data().write(to: folder.appendingPathComponent("notes.txt"))
    // A file with the extension is not a package.
    try Data().write(to: folder.appendingPathComponent("Fake.astrostack"))
    try FileManager.default.createDirectory(
      at: folder.appendingPathComponent(".Hidden.astrostack"), withIntermediateDirectories: true)

    #expect(
      ProjectCatalog.folderListing(of: folder).map(\.lastPathComponent) == [m31.lastPathComponent])
    #expect(ProjectCatalog.folderListing(of: folder.appendingPathComponent("none")).isEmpty)
  }
}
