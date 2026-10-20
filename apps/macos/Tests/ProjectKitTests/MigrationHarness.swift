import Foundation
import GRDB
import ProjectKit

/// Runs `Migrator` on a bare SQLite file, outside a project package.
enum MigrationHarness {
  static func migrate(_ url: URL, catalog: [Migration], to target: Int?) throws {
    let queue = try DatabaseQueue(path: url.path)
    defer { try? queue.close() }
    try queue.write { db in
      try Migrator(migrations: catalog).migrate(db, to: target, now: 1_000)
    }
  }

  static func versions(_ url: URL) throws -> [Int] {
    let queue = try DatabaseQueue(path: url.path)
    defer { try? queue.close() }
    return try queue.read { db in
      try Int.fetchAll(db, sql: "SELECT version FROM schema_migrations ORDER BY version")
    }
  }

  /// Simulates a database whose bookkeeping lost a version.
  static func forget(_ url: URL, version: Int) throws {
    let queue = try DatabaseQueue(path: url.path)
    defer { try? queue.close() }
    try queue.write { db in
      try db.execute(sql: "DELETE FROM schema_migrations WHERE version = ?", arguments: [version])
    }
  }
}
