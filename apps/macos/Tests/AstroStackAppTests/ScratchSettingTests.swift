import AstroStackApp
import Foundation
import TestSupport
import Testing

/// The scratch folder of Settings (card 0098): persisted, read by each run, never a read-only
/// source.
@Suite("ScratchSetting — the runs' scratch folder, chosen in Settings")
struct ScratchSettingTests {
  /// A scratch defaults suite, emptied first (clean state at the start).
  static func suite() throws -> (UserDefaults, String) {
    let name = "fr.astrostack.tests.scratch.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defaults.removePersistentDomain(forName: name)
    return (defaults, name)
  }

  @Test(
    "nothing chosen: $TMPDIR/AstroStack/Work; a choice persists and runs go to its own subfolder")
  func testChoicePersists() throws {
    let (defaults, name) = try Self.suite()
    defer { defaults.removePersistentDomain(forName: name) }
    let astro = URL(fileURLWithPath: "/Users/someone/Documents/astro")
    let setting = ScratchSetting(defaults: defaults, astro: astro)
    #expect(setting.chosen == nil)
    #expect(setting.folder == ScratchSetting.defaultFolder)
    #expect(ScratchSetting.defaultFolder.path.hasSuffix("AstroStack/Work"))

    #expect(setting.choose(URL(fileURLWithPath: "/Volumes/SSD")))
    let reread = ScratchSetting(defaults: defaults, astro: astro)
    #expect(reread.chosen?.path == "/Volumes/SSD")
    #expect(reread.folder.path == "/Volumes/SSD/AstroStack/Work", "never the user's folder itself")

    #expect(setting.choose(nil))
    #expect(ScratchSetting(defaults: defaults, astro: astro).folder == ScratchSetting.defaultFolder)
  }

  @Test(
    "a folder under the read-only sources is refused and nothing is stored (R7), wherever the root",
    arguments: ["captures/M31", "library", "Runs"],
    ["/Users/someone/Documents/astro", "/Volumes/SSD/astro"])
  func testReadOnlySourcesRefused(relative: String, root: String) throws {
    let (defaults, name) = try Self.suite()
    defer { defaults.removePersistentDomain(forName: name) }
    let astro = URL(fileURLWithPath: root)
    let setting = ScratchSetting(defaults: defaults, astro: astro)
    #expect(!setting.choose(astro.appendingPathComponent(relative)))
    #expect(setting.chosen == nil)
  }

  @Test("RunServices reads the folder when a run starts, not when the window opens")
  func testRunServicesReadsTheSettingEachTime() throws {
    let (defaults, name) = try Self.suite()
    defer { defaults.removePersistentDomain(forName: name) }
    nonisolated(unsafe) let setting = ScratchSetting(defaults: defaults)
    let services = RunServices(
      run: { _ in AsyncThrowingStream { $0.finish() } }, scratchFolder: { setting.folder })
    #expect(services.scratch == ScratchSetting.defaultFolder)
    setting.choose(URL(fileURLWithPath: "/Volumes/SSD"))
    #expect(services.scratch.path == "/Volumes/SSD/AstroStack/Work")
  }
}
