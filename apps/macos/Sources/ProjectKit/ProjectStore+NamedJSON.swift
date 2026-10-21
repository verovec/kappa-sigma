internal import Foundation
internal import GRDB

/// The tables that keep a JSON body under a unique name (0001: `pipelines`, `user_profiles`).
enum NamedJSONTable: String {
  /// Saved pipelines (card 0059).
  case pipelines
  /// The user's profile copies (card 0060).
  case userProfiles = "user_profiles"
}

extension ProjectStore {
  /// The names in `table`, sorted.
  func names(in table: NamedJSONTable) throws -> [String] {
    try pool.read { db in
      try String.fetchAll(db, sql: "SELECT name FROM \(table.rawValue) ORDER BY name")
    }
  }

  /// The body saved as `name` in `table`, `nil` when none.
  func body(named name: String, in table: NamedJSONTable) throws -> Data? {
    try pool.read { db in
      try String.fetchOne(
        db, sql: "SELECT body_json FROM \(table.rawValue) WHERE name = ?",
        arguments: [Self.storedName(name)]
      ).map { Data($0.utf8) }
    }
  }

  /// Saves `json` as `name` in `table`; an existing row keeps its id and `created_at`.
  func save(_ json: Data, named name: String, in table: NamedJSONTable) throws {
    let name = Self.storedName(name)
    guard !name.isEmpty else { throw ProjectStoreError.emptyName }
    guard let body = String(bytes: json, encoding: .utf8) else { throw ProjectStoreError.notText }
    let stamp = now()
    try pool.write { db in
      try db.execute(
        sql: """
          INSERT INTO \(table.rawValue) (name, body_json, created_at, updated_at)
          VALUES (?, ?, ?, ?)
          ON CONFLICT (name) DO UPDATE SET body_json = excluded.body_json,
            updated_at = excluded.updated_at
          """,
        arguments: [name, body, stamp, stamp])
    }
  }

  /// Deletes `name` from `table` (nothing when absent).
  func delete(named name: String, in table: NamedJSONTable) throws {
    try pool.write { db in
      try db.execute(
        sql: "DELETE FROM \(table.rawValue) WHERE name = ?", arguments: [Self.storedName(name)])
    }
  }

  /// A name as stored: trimmed of spaces and line breaks, the same for save, read and delete.
  static func storedName(_ name: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
