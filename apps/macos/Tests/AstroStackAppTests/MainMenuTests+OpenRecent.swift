import AppKit
import AstroStackApp
import Foundation
import TestSupport
import Testing

extension MainMenuTests {
  /// Three recent packages in `root`: « M 31 » and « IC 1848 » on disk, « Gone » deleted.
  static func recentPackages(in root: URL) throws -> [URL] {
    let urls = ["M 31", "IC 1848", "Gone"].map { root.appendingPathComponent("\($0).astrostack") }
    for url in urls.prefix(2) {
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    return urls
  }

  /// File › Open Recent's submenu of a bar built with `recents`, filled as when it opens.
  static func openRecent(
    _ recents: RecentProjectsMenu, locale: Locale, file: String, title: String
  ) throws -> NSMenu {
    let bar = MainMenu.make(locale: locale, recentProjects: recents)
    let menu = try #require(bar.items.first { $0.submenu?.title == file }?.submenu)
    let item = try #require(menu.items.first { $0.title == title }, "\(title) in \(file)")
    let submenu = try #require(item.submenu)
    #expect(submenu.delegate === recents)
    recents.menuNeedsUpdate(submenu)
    return submenu
  }

  @Test(
    "Open Recent lists the recent projects still on disk, the open one checked, then Clear Menu",
    .scratchDirectory,
    arguments: [
      (Locale(identifier: "en"), "File", "Open Recent", "Clear Menu"),
      (Locale(identifier: "fr"), "Fichier", "Ouvrir récent", "Effacer le menu"),
    ])
  func testOpenRecent_listsRecentProjects(
    locale: Locale, file: String, title: String, clear: String
  ) throws {
    let urls = try Self.recentPackages(in: ScratchDirectory.url)
    let recents = RecentProjectsMenu(
      recentURLs: { urls }, openKeys: { [WelcomeModel.key(urls[1])] }, open: { _ in })
    let submenu = try Self.openRecent(recents, locale: locale, file: file, title: title)
    #expect(submenu.items.map(\.title) == ["M 31", "IC 1848", "", clear])
    #expect(submenu.items.map(\.isSeparatorItem) == [false, false, true, false])
    #expect(submenu.items.map(\.state) == [.off, .on, .off, .off])
    #expect(submenu.items.last?.action.map(NSStringFromSelector) == "clearRecentProjects:")
    // Opened again after a project closed: rebuilt, never appended.
    recents.menuNeedsUpdate(submenu)
    #expect(submenu.items.count == 4)
  }

  @Test("no recent project: only Clear Menu, without a separator above it", .scratchDirectory)
  func testOpenRecent_empty() throws {
    let recents = RecentProjectsMenu(recentURLs: { [] }, openKeys: { [] }, open: { _ in })
    let submenu = try Self.openRecent(
      recents, locale: Self.english, file: "File", title: "Open Recent")
    #expect(submenu.items.filter { !$0.isHidden }.map(\.title) == ["Clear Menu"])
  }

  @Test("activating a recent project opens that package", .scratchDirectory)
  func testOpenRecent_itemOpensProject() throws {
    let urls = try Self.recentPackages(in: ScratchDirectory.url)
    var opened: [URL] = []
    let recents = RecentProjectsMenu(
      recentURLs: { urls }, openKeys: { [] }, open: { opened.append($0) })
    let submenu = try Self.openRecent(
      recents, locale: Self.english, file: "File", title: "Open Recent")
    submenu.performActionForItem(at: 1)
    #expect(opened == [urls[1]])
  }
}
