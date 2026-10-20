package import GRDB

/// Applies `Migration`s up or down and records them in `schema_migrations`.
///
/// Not GRDB's `DatabaseMigrator`: it has no down migrations, and the schema contract here is
/// SQL files with an up and a down each (card 0068). It keeps DatabaseMigrator's guarantees that
/// matter: an applied migration must still be the catalog's (same name), and versions apply in
/// order without holes. `schema_migrations` is bookkeeping (like golang-migrate's table), not an
/// entity: no id or updated_at.
package struct Migrator {
  /// The catalog, by version.
  package let migrations: [Migration]

  /// A migrator over `migrations` (sorted, contiguous from 1: `MigrationCatalog.parse`).
  package init(migrations: [Migration]) {
    self.migrations = migrations
  }

  /// Brings `db` to `target` (`nil` = the latest), inside the caller's transaction: a failure
  /// leaves the schema as it was. `now` stamps `applied_at` (Unix milliseconds).
  package func migrate(_ db: Database, to target: Int?, now: Int64) throws {
    try db.execute(
      sql: """
        CREATE TABLE IF NOT EXISTS schema_migrations (
          version INTEGER PRIMARY KEY, name TEXT NOT NULL, applied_at INTEGER NOT NULL)
        """)
    let applied = try appliedNames(db)
    let goal = target ?? (migrations.last?.version ?? 0)
    guard goal == 0 || migrations.contains(where: { $0.version == goal }) else {
      throw MigrationError.unknownTarget(goal)
    }
    for migration in migrations where migration.version <= goal {
      guard applied[migration.version] == nil else { continue }
      try db.execute(sql: migration.up)
      try db.execute(
        sql: "INSERT INTO schema_migrations (version, name, applied_at) VALUES (?, ?, ?)",
        arguments: [migration.version, migration.name, now])
    }
    for migration in migrations.reversed() where migration.version > goal {
      guard applied[migration.version] != nil else { continue }
      try db.execute(sql: migration.down)
      try db.execute(
        sql: "DELETE FROM schema_migrations WHERE version = ?", arguments: [migration.version])
    }
  }

  /// The applied versions and names, checked against the catalog.
  private func appliedNames(_ db: Database) throws -> [Int: String] {
    let rows = try Row.fetchAll(db, sql: "SELECT version, name FROM schema_migrations")
    var applied: [Int: String] = [:]
    for row in rows {
      applied[row["version"]] = row["name"]
    }
    let known = Dictionary(uniqueKeysWithValues: migrations.map { ($0.version, $0.name) })
    for (version, name) in applied.sorted(by: { $0.key < $1.key }) {
      guard let expected = known[version] else { throw MigrationError.unknownVersion(version) }
      guard expected == name else {
        throw MigrationError.nameMismatch(version: version, applied: name, catalog: expected)
      }
    }
    if let highest = applied.keys.max(),
      let hole = migrations.first(where: { $0.version < highest && applied[$0.version] == nil })
    {
      throw MigrationError.missingBelow(version: hole.version, applied: highest)
    }
    return applied
  }
}
