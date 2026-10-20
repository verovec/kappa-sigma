internal import Foundation
internal import GRDB

// MARK: - Calibration library index

extension ProjectStore {
  /// Makes the index equal `rows` (the folder's masters, by path) in one transaction: new paths
  /// inserted, changed rows updated, rows whose file is gone deleted.
  @discardableResult
  package func syncCalibrationMasters(_ rows: [CalibrationMasterRow]) throws -> CalibrationSyncReport {
    let stamp = now()
    return try pool.write { db in
      let existing = Dictionary(
        try Row.fetchAll(db, sql: "SELECT * FROM calibration_masters").map { (Self.calibrationMaster($0).path, Self.calibrationMaster($0)) },
        uniquingKeysWith: { $1 })
      var report = CalibrationSyncReport(inserted: 0, updated: 0, deleted: 0)
      for row in rows {
        switch existing[row.path] {
        case .none:
          try Self.insert(row, at: stamp, in: db)
          report.inserted += 1
        case .some(let current) where current != row:
          try Self.update(row, at: stamp, in: db)
          report.updated += 1
        case .some:
          continue
        }
      }
      let kept = Set(rows.map(\.path))
      for path in existing.keys where !kept.contains(path) {
        try db.execute(sql: "DELETE FROM calibration_masters WHERE path = ?", arguments: [path])
        report.deleted += 1
      }
      return report
    }
  }

  /// Every indexed master, by path.
  package func calibrationMasters() throws -> [CalibrationMasterRow] {
    try pool.read { db in
      try Row.fetchAll(db, sql: "SELECT * FROM calibration_masters ORDER BY path").map(Self.calibrationMaster)
    }
  }

  private static let columns = [
    "type", "filter", "exposure_ms", "gain", "\"offset\"", "bin", "temp_milli_c", "has_temp", "session",
    "recipe", "frame_count", "pool_hash", "width", "height", "file_bytes", "file_mtime_ms",
  ]

  private static func values(_ row: CalibrationMasterRow) -> [any DatabaseValueConvertible] {
    [
      row.type, row.filter, row.exposureMs, row.gain, row.offset, row.bin, row.tempMilliC, row.hasTemp,
      row.session, row.recipe, row.frameCount, row.poolHash, row.width, row.height, row.fileBytes,
      row.fileMtimeMs,
    ]
  }

  private static func insert(_ row: CalibrationMasterRow, at stamp: Int64, in db: Database) throws {
    let names = (["path"] + columns + ["created_at", "updated_at"]).joined(separator: ", ")
    let marks = Array(repeating: "?", count: columns.count + 3).joined(separator: ", ")
    try db.execute(
      sql: "INSERT INTO calibration_masters (\(names)) VALUES (\(marks))",
      arguments: StatementArguments([row.path] + values(row) + [stamp, stamp]))
  }

  private static func update(_ row: CalibrationMasterRow, at stamp: Int64, in db: Database) throws {
    let assignments = (columns + ["updated_at"]).map { "\($0) = ?" }.joined(separator: ", ")
    try db.execute(
      sql: "UPDATE calibration_masters SET \(assignments) WHERE path = ?",
      arguments: StatementArguments(values(row) + [stamp, row.path]))
  }

  private static func calibrationMaster(_ row: Row) -> CalibrationMasterRow {
    var master = CalibrationMasterRow(path: row["path"], type: row["type"])
    master.filter = row["filter"]
    master.exposureMs = row["exposure_ms"]
    master.gain = row["gain"]
    master.offset = row["offset"]
    master.bin = row["bin"]
    master.tempMilliC = row["temp_milli_c"]
    master.hasTemp = row["has_temp"]
    master.session = row["session"]
    master.recipe = row["recipe"]
    master.frameCount = row["frame_count"]
    master.poolHash = row["pool_hash"]
    master.width = row["width"]
    master.height = row["height"]
    master.fileBytes = row["file_bytes"]
    master.fileMtimeMs = row["file_mtime_ms"]
    return master
  }
}
