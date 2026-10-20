import Foundation
import ProjectKit
import TestSupport
import Testing

@Suite("MigrationCatalog: NNNN_name.up.sql / .down.sql pairs")
struct MigrationCatalogTests {
  @Test("pairs are sorted by version and keep their SQL")
  func testMigrationCatalog_parse_pairs() throws {
    let migrations = try MigrationCatalog.parse(files: [
      "0002_stacks.up.sql": "CREATE TABLE b (id INTEGER);",
      "0001_init.down.sql": "DROP TABLE a;",
      "0002_stacks.down.sql": "DROP TABLE b;",
      "0001_init.up.sql": "CREATE TABLE a (id INTEGER);",
    ])
    #expect(migrations.map(\.version) == [1, 2])
    #expect(migrations.map(\.name) == ["init", "stacks"])
    #expect(migrations[1].up == "CREATE TABLE b (id INTEGER);")
    #expect(migrations[0].down == "DROP TABLE a;")
  }

  @Test(
    "a broken catalog is refused with the reason",
    arguments: [
      (["0001_init.up.sql": "x"], MigrationError.unpaired(version: 1)),
      (["0001_init.down.sql": "x"], .unpaired(version: 1)),
      (["init.up.sql": "x"], .badFileName("init.up.sql")),
      (["0001_init.sql": "x"], .badFileName("0001_init.sql")),
      (["0000_zero.up.sql": "x", "0000_zero.down.sql": "x"], .badFileName("0000_zero.down.sql")),
      (
        [
          "0001_a.up.sql": "x", "0001_a.down.sql": "x", "0001_b.up.sql": "x",
          "0001_b.down.sql": "x",
        ], .duplicateVersion(1)
      ),
      (
        [
          "0001_a.up.sql": "x", "0001_a.down.sql": "x", "0003_c.up.sql": "x",
          "0003_c.down.sql": "x",
        ],
        .gap(after: 1)
      ),
    ])
  func testMigrationCatalog_parse_rejects(files: [String: String], expected: MigrationError) {
    #expect(throws: expected) { try MigrationCatalog.parse(files: files) }
  }

  @Test("a missing migrations folder is an error, never an empty catalog", .scratchDirectory)
  func testMigrationCatalog_load_missingFolder() throws {
    let folder = try ScratchDirectory.url.appendingPathComponent("Migrations")
    #expect(throws: MigrationError.catalogMissing(path: folder.path)) {
      try MigrationCatalog.load(from: folder)
    }
  }

  @Test("the bundled catalog starts at 0001_init")
  func testMigrationCatalog_bundled() throws {
    let migrations = try MigrationCatalog.bundled()
    #expect(migrations.first?.version == 1)
    #expect(migrations.first?.name == "init")
  }
}
