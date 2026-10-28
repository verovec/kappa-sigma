import AstroStackApp
import Foundation
import StackKit
import TestSupport
import Testing

/// The astro folder of Settings (card 0148): the read-only data root (R7), `~/Documents/astro`
/// unless chosen, with its four subfolders; never a folder the app itself writes under.
@Suite("AstroFolderSetting — the data root chosen in Settings, every path follows")
struct AstroFolderSettingTests {
  static func suite() throws -> (UserDefaults, String) {
    let name = "fr.astrostack.tests.astro.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defaults.removePersistentDomain(forName: name)
    return (defaults, name)
  }

  @Test("testDefaultIsDocumentsAstro: nothing chosen → ~/Documents/astro and its subfolders")
  func testDefaultIsDocumentsAstro() throws {
    let (defaults, name) = try Self.suite()
    defer { defaults.removePersistentDomain(forName: name) }
    let home = URL(fileURLWithPath: "/Users/someone")
    let setting = AstroFolderSetting(defaults: defaults, home: home)
    #expect(setting.chosen == nil)
    #expect(setting.folder.path == "/Users/someone/Documents/astro")
    #expect(setting.captures.path == "/Users/someone/Documents/astro/captures")
    #expect(setting.runs.path == "/Users/someone/Documents/astro/runs")
    #expect(setting.library.path == "/Users/someone/Documents/astro/library")
    #expect(setting.fixtures.path == "/Users/someone/Documents/astro/fixtures")
    #expect(setting.catalogues.path == "/Users/someone/Documents/astro/library/catalogues")
    #expect(AstroFolderSetting.defaultFolder.path.hasSuffix("/Documents/astro"))
  }

  @Test(
    "testChoicePersists: a choice is re-read by a new instance; nil goes back to the default",
    .scratchDirectory)
  func testChoicePersists() throws {
    let (defaults, name) = try Self.suite()
    defer { defaults.removePersistentDomain(forName: name) }
    let root = try ScratchDirectory.url.appendingPathComponent("Volumes/SSD/astro")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let home = URL(fileURLWithPath: "/Users/someone")
    let setting = AstroFolderSetting(defaults: defaults, home: home)
    #expect(setting.choose(root))
    let reread = AstroFolderSetting(defaults: defaults, home: home)
    #expect(reread.chosen?.path == root.standardizedFileURL.path)
    #expect(reread.captures.path == root.standardizedFileURL.path + "/captures")
    #expect(setting.choose(nil))
    #expect(
      AstroFolderSetting(defaults: defaults, home: home).folder.path
        == "/Users/someone/Documents/astro")
  }

  @Test(
    "testAppOwnedFoldersRefused: a root the app writes under cannot be the read-only root",
    .scratchDirectory,
    arguments: [
      "scratch/AstroStack/Work", "home/AstroStack", "home/AstroStack/Projects", "home", "scratch",
      "", "tmp/AstroStack", "tmp/AstroStack/Untitled", "tmp/AstroStack/Work/run_1", "/",
    ])
  func testAppOwnedFoldersRefused(relative: String) throws {
    let (defaults, name) = try Self.suite()
    defer { defaults.removePersistentDomain(forName: name) }
    let base = try ScratchDirectory.url
    let home = base.appendingPathComponent("home")
    let scratch = base.appendingPathComponent("scratch/AstroStack/Work")
    // "tmp/…": the sweep's own roots (Siril's folders, the untitled projects) under a fake
    // temporary folder; "/" is around everything.
    let folder = relative == "/" ? URL(fileURLWithPath: "/") : base.appendingPathComponent(relative)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    let setting = AstroFolderSetting(
      defaults: defaults, home: home, scratch: scratch,
      temporary: base.appendingPathComponent("tmp"))
    #expect(!setting.choose(folder))
    #expect(setting.chosen == nil)
  }

  @Test(
    "testMissingFolderRefused: a path that is no folder is refused, nothing stored",
    .scratchDirectory)
  func testMissingFolderRefused() throws {
    let (defaults, name) = try Self.suite()
    defer { defaults.removePersistentDomain(forName: name) }
    let base = try ScratchDirectory.url
    let file = base.appendingPathComponent("notes.txt")
    try Data().write(to: file)
    let setting = AstroFolderSetting(defaults: defaults, home: base.appendingPathComponent("home"))
    #expect(!setting.choose(base.appendingPathComponent("nowhere")))
    #expect(!setting.choose(file))
    #expect(setting.chosen == nil)
  }

  @Test("testFoldersFollowTheSetting: the import's folders and the sweep's protected roots")
  func testFoldersFollowTheSetting() throws {
    let (defaults, name) = try Self.suite()
    defer { defaults.removePersistentDomain(forName: name) }
    let home = URL(fileURLWithPath: "/Users/someone")
    let setting = AstroFolderSetting(defaults: defaults, home: home)
    #expect(setting.captures.path == "/Users/someone/Documents/astro/captures")
    #expect(setting.library.path == "/Users/someone/Documents/astro/library")
    #expect(setting.catalogues.path == "/Users/someone/Documents/astro/library/catalogues")
    #expect(AppDelegate.protectedFolders(setting).first == setting.folder)
    #expect(AppDelegate.protectedFolders(setting).contains(LeftoverSweep.dataFolder))
  }

  @Test(
    "the Settings lines name each subfolder and whether it exists, nothing decided",
    .scratchDirectory)
  func testAstroLines() async throws {
    let (defaults, name) = try Self.suite()
    defer { defaults.removePersistentDomain(forName: name) }
    let base = try ScratchDirectory.url
    let root = base.appendingPathComponent("astro")
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("library/catalogues"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: base.appendingPathComponent("elsewhere/runs"), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
      at: root.appendingPathComponent("runs"),
      withDestinationURL: base.appendingPathComponent("elsewhere/runs"))
    try FileManager.default.createSymbolicLink(
      at: base.appendingPathComponent("link"), withDestinationURL: root)
    let setting = AstroFolderSetting(defaults: defaults, home: URL(fileURLWithPath: "/Users/x"))
    #expect(setting.choose(base.appendingPathComponent("link")), "a link to a folder is a folder")
    let lines = await AstroFolderModel.lines(under: setting.folder)
    #expect(lines.map(\.name) == ["captures", "runs", "library", "fixtures", "library/catalogues"])
    #expect(lines.map(\.found) == [false, true, true, false, true], "a linked subfolder counts")
  }

  @Test("the catalogue script reads the same key in the same defaults domain as the app")
  func testCatalogueScriptReadsTheSetting() throws {
    let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let script = try String(
      contentsOf: package.appendingPathComponent("../../scripts/download-catalogues.sh"),
      encoding: .utf8)
    let plist = try String(
      contentsOf: package.appendingPathComponent("App/Info.plist"), encoding: .utf8)
    #expect(script.contains("defaults read fr.astrostack.AstroStack \(AstroFolderSetting.key)"))
    #expect(plist.contains("<string>fr.astrostack.AstroStack</string>"))
  }
}
