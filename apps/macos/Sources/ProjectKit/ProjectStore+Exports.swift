internal import Foundation
internal import GRDB

// MARK: - Exports (card 0091)

extension ProjectStore {
  /// Records an export of `imageID` at `headStepID` into `folder`: the settings it ran and the
  /// file names it wrote.
  @discardableResult
  package func addExport(
    stackID: Int64, imageID: Int64, headStepID: Int64?, folder: String, settingsJSON: String,
    files: [String]
  ) throws -> ProjectExport {
    let stamp = now()
    let filesJSON = String(bytes: try JSONEncoder().encode(files), encoding: .utf8) ?? "[]"
    return try pool.write { db in
      try db.execute(
        sql: """
          INSERT INTO exports (stack_id, image_id, head_step_id, folder, settings_json,
            files_json, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          """,
        arguments: [
          stackID, imageID, headStepID, folder, settingsJSON, filesJSON, stamp, stamp,
        ])
      return ProjectExport(
        id: db.lastInsertedRowID, stackID: stackID, imageID: imageID, headStepID: headStepID,
        folder: folder, settingsJSON: settingsJSON, files: files, createdAt: stamp,
        updatedAt: stamp)
    }
  }

  /// The exports of a stack, newest first.
  package func exports(stackID: Int64) throws -> [ProjectExport] {
    try pool.read { db in
      try Row.fetchAll(
        db, sql: "SELECT * FROM exports WHERE stack_id = ? ORDER BY id DESC",
        arguments: [stackID]
      )
      .map { row in
        let filesJSON: String = row["files_json"]
        return ProjectExport(
          id: row["id"], stackID: row["stack_id"], imageID: row["image_id"],
          headStepID: row["head_step_id"], folder: row["folder"],
          settingsJSON: row["settings_json"],
          files: try JSONDecoder().decode([String].self, from: Data(filesJSON.utf8)),
          createdAt: row["created_at"], updatedAt: row["updated_at"])
      }
    }
  }
}
