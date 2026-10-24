internal import Foundation
internal import GRDB

// MARK: - Sources and stacks

extension ProjectStore {
  /// Records a source folder (read-only) and returns it; recording the same (kind, path) again,
  /// however the path is spelled (`./`, `..`, trailing slash), returns the existing row.
  @discardableResult
  package func addSource(kind: ProjectSource.Kind, path: String) throws -> ProjectSource {
    let canonical = URL(fileURLWithPath: path).standardizedFileURL.path
    let stamp = now()
    return try pool.write { db in
      try db.execute(
        sql: """
          INSERT INTO sources (kind, path, read_only, created_at, updated_at)
          VALUES (?, ?, 1, ?, ?) ON CONFLICT (kind, path) DO NOTHING
          """,
        arguments: [kind.rawValue, canonical, stamp, stamp])
      let row = try Row.fetchOne(
        db, sql: "SELECT * FROM sources WHERE kind = ? AND path = ?",
        arguments: [kind.rawValue, canonical])
      guard let row else { throw DatabaseError(resultCode: .SQLITE_INTERNAL) }
      return Self.source(row)
    }
  }

  /// Records `profileID` (`nil`: none) as the profile kept for the source of `kind` at `path`.
  package func setProfile(_ profileID: String?, kind: ProjectSource.Kind, path: String) throws {
    let canonical = URL(fileURLWithPath: path).standardizedFileURL.path
    let stamp = now()
    try pool.write { db in
      try db.execute(
        sql: "UPDATE sources SET profile_id = ?, updated_at = ? WHERE kind = ? AND path = ?",
        arguments: [profileID, stamp, kind.rawValue, canonical])
    }
  }

  /// Every source, by id.
  package func sources() throws -> [ProjectSource] {
    try pool.read { db in
      try Row.fetchAll(db, sql: "SELECT * FROM sources ORDER BY id").map(Self.source)
    }
  }

  private static func source(_ row: Row) -> ProjectSource {
    ProjectSource(
      id: row["id"], kind: ProjectSource.Kind(rawValue: row["kind"]) ?? .night,
      path: row["path"], readOnly: row["read_only"], profileID: row["profile_id"],
      createdAt: row["created_at"], updatedAt: row["updated_at"])
  }

  /// Records a stack, the sources it was built from and one image per `imageRoles`.
  ///
  /// One transaction: a failure leaves no half-recorded stack. `object` and `scopeJSON` (card
  /// 0095) name what the run stacked; a stack of every light of its sources leaves them empty. A
  /// paused run (card 0097) is recorded with `status: .paused` and its checkpoint, without images.
  @discardableResult
  package func addStack(
    bundlePath: String, sourceIDs: [Int64], paramsJSON: String, imageRoles: [String] = [],
    object: String = "", scopeJSON: String? = nil, status: ProjectStack.Status = .done,
    checkpointJSON: String? = nil
  ) throws -> ProjectStack {
    let stamp = now()
    return try pool.write { db in
      try db.execute(
        sql: """
          INSERT INTO stacks (bundle_path, params_json, object, scope_json, status,
            checkpoint_json, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          """,
        arguments: [
          bundlePath, paramsJSON, object, scopeJSON, status.rawValue, checkpointJSON, stamp, stamp,
        ])
      let id = db.lastInsertedRowID
      for source in Set(sourceIDs) {
        try db.execute(
          sql: """
            INSERT INTO stack_sources (stack_id, source_id, created_at, updated_at)
            VALUES (?, ?, ?, ?)
            """,
          arguments: [id, source, stamp, stamp])
      }
      for role in imageRoles {
        try db.execute(
          sql: "INSERT INTO images (stack_id, role, created_at, updated_at) VALUES (?, ?, ?, ?)",
          arguments: [id, role, stamp, stamp])
      }
      return ProjectStack(
        id: id, bundlePath: bundlePath, sourceIDs: Set(sourceIDs).sorted(),
        paramsJSON: paramsJSON, object: object, scopeJSON: scopeJSON, status: status,
        checkpointJSON: checkpointJSON, createdAt: stamp, updatedAt: stamp)
    }
  }

  /// The stack `id`, or `nil`.
  package func stack(id: Int64) throws -> ProjectStack? {
    try pool.read { db in
      try Row.fetchOne(db, sql: "SELECT * FROM stacks WHERE id = ?", arguments: [id])
        .map { try Self.stack($0, in: db) }
    }
  }

  /// The newest finished stack, or `nil`.
  package func latestStack() throws -> ProjectStack? {
    try pool.read { db in
      try Row.fetchOne(
        db, sql: "SELECT * FROM stacks WHERE status = 'done' ORDER BY id DESC LIMIT 1"
      ).map { try Self.stack($0, in: db) }
    }
  }

  /// Every finished stack, oldest first (a paused run is listed by `pausedStacks()`).
  package func stacks() throws -> [ProjectStack] {
    try pool.read { db in
      try Row.fetchAll(db, sql: "SELECT * FROM stacks WHERE status = 'done' ORDER BY id")
        .map { try Self.stack($0, in: db) }
    }
  }

  static func stack(_ row: Row, in db: Database) throws -> ProjectStack {
    let id: Int64 = row["id"]
    let sources = try Int64.fetchAll(
      db, sql: "SELECT source_id FROM stack_sources WHERE stack_id = ? ORDER BY source_id",
      arguments: [id])
    return ProjectStack(
      id: id, bundlePath: row["bundle_path"], sourceIDs: sources,
      paramsJSON: row["params_json"], object: row["object"] ?? "", scopeJSON: row["scope_json"],
      status: (row["status"] as String?).flatMap(ProjectStack.Status.init(rawValue:)) ?? .done,
      checkpointJSON: row["checkpoint_json"], openedAt: row["opened_at"],
      createdAt: row["created_at"],
      updatedAt: row["updated_at"])
  }
}
