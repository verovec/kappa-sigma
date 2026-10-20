import Foundation
import TestSupport
import Testing

@Suite("LiveFixtures finds ~/Documents/astro/fixtures, or reports it absent")
struct FixtureRootTests {
  @Test("an empty home has no fixture root", .scratchDirectory)
  func testFixtureRoot_root_absent() throws {
    #expect(LiveFixtures.root(home: try ScratchDirectory.url) == nil)
  }

  @Test("a home with Documents/astro/fixtures has that root", .scratchDirectory)
  func testFixtureRoot_root_present() throws {
    let home = try ScratchDirectory.url
    let fixtures = home.appendingPathComponent("Documents/astro/fixtures", isDirectory: true)
    try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
    #expect(LiveFixtures.root(home: home)?.standardizedFileURL == fixtures.standardizedFileURL)
  }

  @Test("a plain file where the folder should be does not count", .scratchDirectory)
  func testFixtureRoot_root_fileIsNotAFolder() throws {
    let home = try ScratchDirectory.url
    let astro = home.appendingPathComponent("Documents/astro", isDirectory: true)
    try FileManager.default.createDirectory(at: astro, withIntermediateDirectories: true)
    try Data().write(to: astro.appendingPathComponent("fixtures"))
    #expect(LiveFixtures.root(home: home) == nil)
  }
}
