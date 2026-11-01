internal import Foundation
internal import GRDB

// MARK: - Exports (cards 0091, 0152)

extension ProjectStore {
  /// Records an export of `imageID` at `headStepID`: the folder it wrote into (`nil` for S3
  /// only), the settings it ran, the file names, and its S3 copy when it has one.
  @discardableResult
  package func addExport(
    stackID: Int64, imageID: Int64, headStepID: Int64?, folder: String?, settingsJSON: String,
    files: [String], remoteURL: String? = nil,
    remoteStatus: ProjectExport.RemoteStatus = .none, remoteError: String? = nil,
    remoteConnection: String? = nil
  ) throws -> ProjectExport {
    let stamp = now()
    let filesJSON = String(bytes: try JSONEncoder().encode(files), encoding: .utf8) ?? "[]"
    return try pool.write { db in
      try db.execute(
        sql: """
          INSERT INTO exports (stack_id, image_id, head_step_id, folder, settings_json,
            files_json, remote_url, remote_status, remote_error, remote_connection, created_at,
            updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          """,
        arguments: [
          stackID, imageID, headStepID, folder, settingsJSON, filesJSON, remoteURL,
          remoteStatus.rawValue, remoteError, remoteConnection, stamp, stamp,
        ])
      return ProjectExport(
        id: db.lastInsertedRowID, stackID: stackID, imageID: imageID, headStepID: headStepID,
        folder: folder, settingsJSON: settingsJSON, files: files, remoteURL: remoteURL,
        remoteStatus: remoteStatus, remoteError: remoteError, remoteConnection: remoteConnection,
        createdAt: stamp, updatedAt: stamp)
    }
  }

  /// Where export `exportID`'s S3 copy stands now (« Resend to S3 »), with the reason of a
  /// failure.
  package func setRemoteStatus(
    exportID: Int64, _ status: ProjectExport.RemoteStatus, error: String?
  ) throws {
    let stamp = now()
    try pool.write { db in
      try db.execute(
        sql: """
          UPDATE exports SET remote_status = ?, remote_error = ?, updated_at = ? WHERE id = ?
          """,
        arguments: [status.rawValue, error, stamp, exportID])
    }
  }

  /// The exports of a stack, newest first.
  package func exports(stackID: Int64) throws -> [ProjectExport] {
    try pool.read { db in
      let hasRemote = try db.columns(in: "exports").contains { $0.name == "remote_status" }
      return try Row.fetchAll(
        db, sql: "SELECT * FROM exports WHERE stack_id = ? ORDER BY id DESC",
        arguments: [stackID]
      )
      .map { row in try Self.export(row, hasRemote: hasRemote) }
    }
  }

  /// A row as read; `hasRemote` false below 0009 (a database migrated down still reads).
  private static func export(_ row: Row, hasRemote: Bool) throws -> ProjectExport {
    let filesJSON: String = row["files_json"]
    let status: String = hasRemote ? row["remote_status"] : "none"
    return ProjectExport(
      id: row["id"], stackID: row["stack_id"], imageID: row["image_id"],
      headStepID: row["head_step_id"], folder: row["folder"], settingsJSON: row["settings_json"],
      files: try JSONDecoder().decode([String].self, from: Data(filesJSON.utf8)),
      remoteURL: hasRemote ? row["remote_url"] : nil,
      remoteStatus: ProjectExport.RemoteStatus(rawValue: status) ?? .none,
      remoteError: hasRemote ? row["remote_error"] : nil,
      remoteConnection: hasRemote ? row["remote_connection"] : nil,
      createdAt: row["created_at"], updatedAt: row["updated_at"])
  }

  /// The indexes of `table`, sorted (SQLite's automatic ones excluded).
  package func indexNames(of table: String) throws -> [String] {
    try pool.read { db in
      try String.fetchAll(
        db,
        sql: """
          SELECT name FROM sqlite_master
          WHERE type = 'index' AND tbl_name = ? AND name NOT LIKE 'sqlite_%' ORDER BY name
          """,
        arguments: [table])
    }
  }
}
