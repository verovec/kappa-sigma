package import Foundation
internal import GRDB

// MARK: - Pipelines (card 0059)

extension ProjectStore {
  /// The names of the saved pipelines, sorted.
  package func pipelineNames() throws -> [String] {
    try pool.read { db in
      try String.fetchAll(db, sql: "SELECT name FROM pipelines ORDER BY name")
    }
  }

  /// The JSON of the pipeline `name` (as ProcessKit's `Pipeline.json()` wrote it), `nil` when
  /// none has that name.
  package func pipeline(named name: String) throws -> Data? {
    try pool.read { db in
      try String.fetchOne(
        db, sql: "SELECT body_json FROM pipelines WHERE name = ?",
        arguments: [Self.pipelineName(name)]
      ).map { Data($0.utf8) }
    }
  }

  /// Saves `json` as the pipeline `name` (« Save pipeline as… »); an existing one of that name
  /// is overwritten, keeping its row and `created_at`.
  package func savePipeline(named name: String, json: Data) throws {
    let name = Self.pipelineName(name)
    guard !name.isEmpty else { throw ProjectStoreError.emptyName }
    guard let body = String(bytes: json, encoding: .utf8) else { throw ProjectStoreError.notText }
    let stamp = now()
    try pool.write { db in
      try db.execute(
        sql: """
          INSERT INTO pipelines (name, body_json, created_at, updated_at) VALUES (?, ?, ?, ?)
          ON CONFLICT (name) DO UPDATE SET body_json = excluded.body_json,
            updated_at = excluded.updated_at
          """,
        arguments: [name, body, stamp, stamp])
    }
  }

  /// Deletes the pipeline `name` (nothing when there is none).
  package func deletePipeline(named name: String) throws {
    try pool.write { db in
      try db.execute(
        sql: "DELETE FROM pipelines WHERE name = ?", arguments: [Self.pipelineName(name)])
    }
  }

  /// A pipeline name as stored: trimmed of spaces and line breaks, the same for save, read and
  /// delete.
  static func pipelineName(_ name: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
