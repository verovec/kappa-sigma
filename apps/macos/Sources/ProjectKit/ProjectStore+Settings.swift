internal import GRDB

// MARK: - Settings and summary

extension ProjectStore {
  /// The value of setting `key`, `nil` when it was never written.
  package func setting(_ key: String) throws -> String? {
    try pool.read { db in
      try String.fetchOne(
        db, sql: "SELECT value FROM project_settings WHERE key = ?", arguments: [key])
    }
  }

  /// Writes setting `key`; an existing row keeps its id and `created_at`.
  package func setSetting(_ key: String, to value: String) throws {
    let stamp = now()
    try pool.write { db in
      try db.execute(
        sql: """
          INSERT INTO project_settings (key, value, created_at, updated_at) VALUES (?, ?, ?, ?)
          ON CONFLICT (key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
          """,
        arguments: [key, value, stamp, stamp])
    }
  }

  /// Every setting, by key.
  package func settings() throws -> [ProjectSetting] {
    try pool.read { db in
      try Row.fetchAll(db, sql: "SELECT * FROM project_settings ORDER BY key").map { row in
        ProjectSetting(
          id: row["id"], key: row["key"], value: row["value"], createdAtMs: row["created_at"],
          updatedAtMs: row["updated_at"])
      }
    }
  }

  /// The project's counts, read in one snapshot.
  package func summary() throws -> ProjectSummary {
    try pool.read(Self.summary(in:))
  }

  /// The counts as `db` holds them; shared by an open store and a read-only peek.
  ///
  /// The peek never migrates, so a table a newer migration adds counts 0 in an older package.
  static func summary(in db: Database) throws -> ProjectSummary {
    func count(_ table: String) throws -> Int {
      guard try db.tableExists(table) else { return 0 }
      return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? 0
    }
    return ProjectSummary(
      sources: try count("sources"), stacks: try count("stacks"), images: try count("images"),
      historySteps: try count("history_steps"), exports: try count("exports"))
  }
}
