internal import GRDB

// MARK: - Images, history, snapshots, disk budget

extension ProjectStore {
  /// Records an image of a stack, with no history yet.
  @discardableResult
  package func addImage(stackID: Int64, role: String) throws -> ProjectImage {
    let stamp = now()
    return try pool.write { db in
      try db.execute(
        sql: "INSERT INTO images (stack_id, role, created_at, updated_at) VALUES (?, ?, ?, ?)",
        arguments: [stackID, role, stamp, stamp])
      return ProjectImage(
        id: db.lastInsertedRowID, stackID: stackID, role: role, headStepID: nil,
        createdAt: stamp, updatedAt: stamp)
    }
  }

  /// The images of a stack, by id.
  package func images(stackID: Int64) throws -> [ProjectImage] {
    try pool.read { db in
      try Row.fetchAll(
        db, sql: "SELECT * FROM images WHERE stack_id = ? ORDER BY id", arguments: [stackID]
      )
      .map { row in
        ProjectImage(
          id: row["id"], stackID: row["stack_id"], role: row["role"],
          headStepID: row["head_step_id"], createdAt: row["created_at"],
          updatedAt: row["updated_at"])
      }
    }
  }

  /// Appends a step at the end of the image's history and makes it the image's head.
  @discardableResult
  package func appendHistoryStep(
    imageID: Int64, processID: String, paramsJSON: String, output: HistoryStep.Output?,
    contentHash: String?
  ) throws -> HistoryStep {
    let stamp = now()
    return try pool.write { db in
      let last = try Int.fetchOne(
        db, sql: "SELECT MAX(ordinal) FROM history_steps WHERE image_id = ?", arguments: [imageID])
      let ordinal = (last ?? 0) + 1
      try db.execute(
        sql: """
          INSERT INTO history_steps (image_id, ordinal, process_id, params_json, output_path,
            output_bytes, content_hash, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
          """,
        arguments: [
          imageID, ordinal, processID, paramsJSON, output?.path, output?.bytes ?? 0, contentHash,
          stamp, stamp,
        ])
      let id = db.lastInsertedRowID
      try db.execute(
        sql: "UPDATE images SET head_step_id = ?, updated_at = ? WHERE id = ?",
        arguments: [id, stamp, imageID])
      return HistoryStep(
        id: id, imageID: imageID, ordinal: ordinal, processID: processID, paramsJSON: paramsJSON,
        outputPath: output?.path, outputBytes: output?.bytes ?? 0, contentHash: contentHash,
        createdAt: stamp, updatedAt: stamp)
    }
  }

  /// Makes `stepID` the image's head (`nil`: the original), keeping every step: undo and redo
  /// move the head, a new step after an undo deletes the undone ones (card 0087).
  package func setHead(imageID: Int64, stepID: Int64?) throws {
    let stamp = now()
    try pool.write { db in
      if let stepID {
        let owner = try Int64.fetchOne(
          db, sql: "SELECT image_id FROM history_steps WHERE id = ?", arguments: [stepID])
        guard owner == imageID else {
          throw ProjectStoreError.notImageStep(imageID: imageID, stepID: stepID)
        }
      }
      try db.execute(
        sql: "UPDATE images SET head_step_id = ?, updated_at = ? WHERE id = ?",
        arguments: [stepID, stamp, imageID])
    }
  }

  /// The image's history, by ordinal.
  package func history(imageID: Int64) throws -> [HistoryStep] {
    try pool.read { db in
      try Row.fetchAll(
        db, sql: "SELECT * FROM history_steps WHERE image_id = ? ORDER BY ordinal",
        arguments: [imageID]
      )
      .map { row in
        HistoryStep(
          id: row["id"], imageID: row["image_id"], ordinal: row["ordinal"],
          processID: row["process_id"], paramsJSON: row["params_json"],
          outputPath: row["output_path"], outputBytes: row["output_bytes"],
          contentHash: row["content_hash"], createdAt: row["created_at"],
          updatedAt: row["updated_at"])
      }
    }
  }

  /// Deletes a step and its file reference; refused while a snapshot names the step.
  ///
  /// Returns the output the step held, for the caller (who owns the package's files) to delete:
  /// the disk budget stops counting it at once. A deleted head moves back to the previous step.
  @discardableResult
  package func deleteHistoryStep(id: Int64) throws -> HistoryStep.Output? {
    let stamp = now()
    return try pool.write { db in
      guard
        let row = try Row.fetchOne(
          db,
          sql:
            "SELECT image_id, ordinal, output_path, output_bytes FROM history_steps WHERE id = ?",
          arguments: [id])
      else { return nil }
      let imageID: Int64 = row["image_id"]
      let ordinal: Int = row["ordinal"]
      try db.execute(sql: "DELETE FROM history_steps WHERE id = ?", arguments: [id])
      try db.execute(
        sql: """
          UPDATE images SET updated_at = ?, head_step_id = (
            SELECT id FROM history_steps WHERE image_id = ? AND ordinal < ?
            ORDER BY ordinal DESC LIMIT 1)
          WHERE id = ? AND head_step_id IS NULL
          """,
        arguments: [stamp, imageID, ordinal, imageID])
      let path: String? = row["output_path"]
      return path.map { HistoryStep.Output(path: $0, bytes: row["output_bytes"]) }
    }
  }

  /// Names a point of the image's history.
  @discardableResult
  package func addSnapshot(imageID: Int64, name: String, stepID: Int64) throws -> ImageSnapshot {
    let stamp = now()
    return try pool.write { db in
      try db.execute(
        sql: """
          INSERT INTO snapshots (image_id, step_id, name, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?)
          """,
        arguments: [imageID, stepID, name, stamp, stamp])
      return ImageSnapshot(
        id: db.lastInsertedRowID, imageID: imageID, stepID: stepID, name: name, createdAt: stamp,
        updatedAt: stamp)
    }
  }

  /// The image's snapshots, by id.
  package func snapshots(imageID: Int64) throws -> [ImageSnapshot] {
    try pool.read { db in
      try Row.fetchAll(
        db, sql: "SELECT * FROM snapshots WHERE image_id = ? ORDER BY id", arguments: [imageID]
      )
      .map { row in
        ImageSnapshot(
          id: row["id"], imageID: row["image_id"], stepID: row["step_id"], name: row["name"],
          createdAt: row["created_at"], updatedAt: row["updated_at"])
      }
    }
  }

  /// Bytes held by history outputs: what the Studio shows as the project's disk budget.
  package func diskBudgetBytes() throws -> Int64 {
    try pool.read { db in
      try Int64.fetchOne(
        db,
        sql:
          "SELECT COALESCE(SUM(output_bytes), 0) FROM history_steps WHERE output_path IS NOT NULL"
      ) ?? 0
    }
  }
}
