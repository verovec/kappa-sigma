import Foundation
import ProjectKit
import TestSupport
import Testing

@Suite("Migrator refuses a database whose history disagrees with the catalog")
struct MigratorTests {
  static let one = Migration(
    version: 1, name: "a", up: "CREATE TABLE a (id INTEGER);", down: "DROP TABLE a;")
  static let two = Migration(
    version: 2, name: "b", up: "CREATE TABLE b (id INTEGER);", down: "DROP TABLE b;")

  @Test("an applied version whose name differs from the catalog is refused", .scratchDirectory)
  func testMigrator_rejectsRenamedMigration() throws {
    let url = try ScratchDirectory.url.appendingPathComponent("t.sqlite")
    try MigrationHarness.migrate(url, catalog: [Self.one], to: nil)
    let renamed = Migration(version: 1, name: "renamed", up: Self.one.up, down: Self.one.down)
    #expect(throws: MigrationError.nameMismatch(version: 1, applied: "a", catalog: "renamed")) {
      try MigrationHarness.migrate(url, catalog: [renamed], to: nil)
    }
  }

  @Test("a hole under an applied version is refused", .scratchDirectory)
  func testMigrator_rejectsHoleBelowApplied() throws {
    let url = try ScratchDirectory.url.appendingPathComponent("t.sqlite")
    try MigrationHarness.migrate(url, catalog: [Self.one, Self.two], to: nil)
    try MigrationHarness.forget(url, version: 1)
    #expect(throws: MigrationError.missingBelow(version: 1, applied: 2)) {
      try MigrationHarness.migrate(url, catalog: [Self.one, Self.two], to: nil)
    }
  }

  @Test("down to 1 then up again replays only version 2", .scratchDirectory)
  func testMigrator_downThenUp() throws {
    let url = try ScratchDirectory.url.appendingPathComponent("t.sqlite")
    try MigrationHarness.migrate(url, catalog: [Self.one, Self.two], to: nil)
    try MigrationHarness.migrate(url, catalog: [Self.one, Self.two], to: 1)
    #expect(try MigrationHarness.versions(url) == [1])
    try MigrationHarness.migrate(url, catalog: [Self.one, Self.two], to: nil)
    #expect(try MigrationHarness.versions(url) == [1, 2])
  }
}
