internal import Foundation
internal import GRDB

/// Typed access to a project's `project.db` (schema: `SCHEMA.md`, migrations: `Migrations/`).
///
/// Every write sets `created_at` / `updated_at` in Unix milliseconds from `now`. Queries are
/// parameterized SQL; the models stay plain values so no other module sees GRDB.
package struct ProjectStore: Sendable {
  let pool: DatabasePool
  let migrations: [Migration]
  let now: @Sendable () -> Int64

  /// Wraps an open pool; `now` is the clock for timestamps (Unix milliseconds).
  init(
    pool: DatabasePool, migrations: [Migration],
    now: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }
  ) {
    self.pool = pool
    self.migrations = migrations
    self.now = now
  }

  // MARK: - Schema

  /// Migrates to `version` (`nil` = the latest, `0` = an empty schema), in one transaction.
  package func migrate(to version: Int?) throws {
    let migrator = Migrator(migrations: migrations)
    let stamp = now()
    try pool.write { db in try migrator.migrate(db, to: version, now: stamp) }
  }

  /// The migrations applied to this database, by version.
  package func appliedMigrations() throws -> [AppliedMigration] {
    try pool.read { db in
      try Row.fetchAll(
        db, sql: "SELECT version, name, applied_at FROM schema_migrations ORDER BY version"
      )
      .map {
        AppliedMigration(version: $0["version"], name: $0["name"], appliedAtMs: $0["applied_at"])
      }
    }
  }

  /// The columns of `table`, sorted (a migration test reads them).
  package func columnNames(of table: String) throws -> [String] {
    try pool.read { db in
      try Row.fetchAll(db, sql: "SELECT name FROM pragma_table_info(?)", arguments: [table])
        .map { $0["name"] as String }.sorted()
    }
  }

  /// The tables of the database, sorted (SQLite's own tables excluded).
  package func tableNames() throws -> [String] {
    try pool.read { db in
      try String.fetchAll(
        db,
        sql: """
          SELECT name FROM sqlite_master
          WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name
          """)
    }
  }
}
