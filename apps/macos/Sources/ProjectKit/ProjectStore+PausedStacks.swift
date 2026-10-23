internal import Foundation
internal import GRDB

/// A paused run's stack row (card 0097): listed apart, completed in place by Continue, deleted by
/// Discard.
extension ProjectStore {
  /// Every paused run, oldest first.
  package func pausedStacks() throws -> [ProjectStack] {
    try pool.read { db in
      try Row.fetchAll(db, sql: "SELECT * FROM stacks WHERE status = 'paused' ORDER BY id")
        .map { try Self.stack($0, in: db) }
    }
  }

  /// The paused run `id`, finished: status done, checkpoint cleared, the parameters it ran and
  /// one image per `imageRoles`, in one transaction.
  @discardableResult
  package func completeStack(id: Int64, paramsJSON: String, imageRoles: [String]) throws
    -> ProjectStack
  {
    let stamp = now()
    return try pool.write { db in
      try Self.requirePaused(id, in: db)
      try db.execute(
        sql: """
          UPDATE stacks SET status = 'done', checkpoint_json = NULL, params_json = ?, updated_at = ?
          WHERE id = ?
          """,
        arguments: [paramsJSON, stamp, id])
      for role in imageRoles {
        try db.execute(
          sql: "INSERT INTO images (stack_id, role, created_at, updated_at) VALUES (?, ?, ?, ?)",
          arguments: [id, role, stamp, stamp])
      }
      let row = try Row.fetchOne(db, sql: "SELECT * FROM stacks WHERE id = ?", arguments: [id])
      guard let row else { throw ProjectStoreError.notPaused(stackID: id) }
      return try Self.stack(row, in: db)
    }
  }

  /// The paused run `id` paused again after a Continue: its new record and checkpoint.
  package func updatePausedStack(id: Int64, paramsJSON: String, checkpointJSON: String) throws {
    let stamp = now()
    try pool.write { db in
      try Self.requirePaused(id, in: db)
      try db.execute(
        sql: """
          UPDATE stacks SET params_json = ?, checkpoint_json = ?, updated_at = ? WHERE id = ?
          """,
        arguments: [paramsJSON, checkpointJSON, stamp, id])
    }
  }

  /// Deletes the paused run `id` (its source links cascade); a finished stack is refused.
  package func deletePausedStack(id: Int64) throws {
    try pool.write { db in
      try Self.requirePaused(id, in: db)
      try db.execute(sql: "DELETE FROM stacks WHERE id = ?", arguments: [id])
    }
  }

  private static func requirePaused(_ id: Int64, in db: Database) throws {
    let status = try String.fetchOne(
      db, sql: "SELECT status FROM stacks WHERE id = ?", arguments: [id])
    guard status == ProjectStack.Status.paused.rawValue else {
      throw ProjectStoreError.notPaused(stackID: id)
    }
  }
}
