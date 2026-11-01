import AstroStackApp
import Foundation
import ProcessKit
import TestSupport
import Testing

/// Where exports go (card 0151): a remembered base folder, `~/Pictures/AstroStack` unless
/// chosen, and a sub-path template; never inside the read-only sources or what the app writes.
@Suite("ExportDestinationSetting — the remembered base folder and sub-path template")
struct ExportDestinationSettingTests {
  static func suite() throws -> (UserDefaults, String) {
    let name = "fr.astrostack.tests.export.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defaults.removePersistentDomain(forName: name)
    return (defaults, name)
  }

  @Test(
    "testDefaultAndPersistence: ~/Pictures/AstroStack + the standard template, then chosen",
    .scratchDirectory)
  func testDefaultAndPersistence() throws {
    let (defaults, name) = try Self.suite()
    defer { defaults.removePersistentDomain(forName: name) }
    let home = try ScratchDirectory.url.appendingPathComponent("home")
    let setting = ExportDestinationSetting(suite: name, home: home)
    #expect(setting.chosenBase == nil)
    #expect(setting.base.path == home.path + "/Pictures/AstroStack")
    #expect(setting.template == ExportPathTemplate(ExportPathTemplate.standard))
    #expect(ExportDestinationSetting.defaultBase.path.hasSuffix("/Pictures/AstroStack"))

    let chosen = try ScratchDirectory.url.appendingPathComponent("Volumes/NAS/Astro")
    try FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: true)
    #expect(setting.choose(chosen) == nil)
    #expect(setting.choose(template: "{object}/{date}") == nil)
    let reread = ExportDestinationSetting(suite: name, home: home)
    #expect(reread.base.path == chosen.standardizedFileURL.path)
    #expect(reread.template.text == "{object}/{date}")

    #expect(
      setting.choose(template: "{nope}")
        == .unknownToken("nope", valid: ExportPathTemplate.tokens))
    #expect(reread.template.text == "{object}/{date}", "a refused template keeps the last one")
    #expect(setting.choose(nil) == nil && setting.choose(template: nil) == nil)
    #expect(reread.chosenBase == nil && reread.template.text == ExportPathTemplate.standard)
  }

  @Test(
    "testRefusals: read-only sources, the projects, the scratch folder, a missing path",
    .scratchDirectory,
    arguments: [
      ("astro/captures/M31", ExportDestinationSetting.Refusal.readOnly),
      ("astro/Runs", .readOnly),
      ("home/AstroStack/Projects", .appOwned),
      ("home/AstroStack", .appOwned),
      ("scratch/AstroStack/Work/out", .appOwned),
      ("missing", .notAFolder),
    ])
  func testRefusals(relative: String, refusal: ExportDestinationSetting.Refusal) throws {
    let (defaults, name) = try Self.suite()
    defer { defaults.removePersistentDomain(forName: name) }
    let base = try ScratchDirectory.url
    let astro = base.appendingPathComponent("astro")
    let scratch = base.appendingPathComponent("scratch/AstroStack/Work")
    try FileManager.default.createDirectory(
      at: astro.appendingPathComponent("runs"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: base.appendingPathComponent("home"), withIntermediateDirectories: true)
    defaults.set(astro.path, forKey: AstroFolderSetting.key)
    let folder = base.appendingPathComponent(relative)
    if relative != "missing" {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    let setting = ExportDestinationSetting(
      suite: name, home: base.appendingPathComponent("home"), scratch: scratch,
      temporary: base.appendingPathComponent("tmp"))

    #expect(setting.choose(folder) == refusal)
    #expect(setting.chosenBase == nil, "nothing stored")
    // Around what the app writes is fine: the home folder holds ~/AstroStack.
    #expect(setting.choose(base.appendingPathComponent("home")) == nil)
  }

  @Test("the base is created on first export only under Pictures or once chosen", .scratchDirectory)
  func testMayCreate() throws {
    let (defaults, name) = try Self.suite()
    defer { defaults.removePersistentDomain(forName: name) }
    let home = try ScratchDirectory.url.appendingPathComponent("home")
    let setting = ExportDestinationSetting(suite: name, home: home)
    #expect(setting.mayCreate(setting.base))
    #expect(setting.mayCreate(home.appendingPathComponent("Pictures/Deep/Sky")))
    #expect(!setting.mayCreate(URL(fileURLWithPath: "/Volumes/Unplugged/Astro")))
    #expect(!setting.mayCreate(home.appendingPathComponent("Picturesque")))
  }
}
