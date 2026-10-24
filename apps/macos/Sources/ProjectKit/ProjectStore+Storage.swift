package import Foundation
internal import GRDB
internal import OSLog

// MARK: - Storage (card 0114)

extension ProjectStore {
  /// Deletes stack `id`: its rows in one transaction, then its folder.
  ///
  /// Refuses the stack open in the Studio (`openStackID`); an unknown id does nothing; throws
  /// only when the rows were not deleted.
  /// Snapshots go first: their step is `ON DELETE RESTRICT`, so the cascade from `stacks` would
  /// stop on them. The folder is removed only when the bundle path is `stacks/<name>` of
  /// `packageFolder`: a stack can never take anything else with it. Rows go before the folder: a
  /// folder that fails to go is a leftover the next open lists (card 0113), never a row whose
  /// files are half gone.
  package func deleteStack(id: Int64, packageFolder: URL, openStackID: Int64?) throws {
    guard id != openStackID else { throw ProjectStoreError.stackOpen(stackID: id) }
    let bundlePath = try pool.write { db -> String? in
      let path = try String.fetchOne(
        db, sql: "SELECT bundle_path FROM stacks WHERE id = ?", arguments: [id])
      guard path != nil else { return nil }
      try db.execute(
        sql: "DELETE FROM snapshots WHERE image_id IN (SELECT id FROM images WHERE stack_id = ?)",
        arguments: [id])
      try db.execute(sql: "DELETE FROM stacks WHERE id = ?", arguments: [id])
      return path
    }
    guard let bundlePath else { return }
    guard let folder = Self.stackFolder(bundlePath, in: packageFolder) else {
      Self.storageLogger.notice("stack \(id) deleted; its folder \(bundlePath) is not in stacks/")
      return
    }
    // The rows are gone: the delete happened. A folder that resists is logged and left as a
    // leftover the next open lists (card 0113), never reported as a stack still there.
    do {
      if FileManager.default.fileExists(atPath: folder.path) {
        try FileManager.default.removeItem(at: folder)
      }
      Self.storageLogger.notice("stack \(id) deleted with its folder \(folder.path)")
    } catch {
      Self.storageLogger.error("stack \(id) deleted; its folder \(folder.path) stays: \(error)")
    }
  }

  /// Records that the Studio opened stack `id` now.
  package func markStackOpened(id: Int64) throws {
    let stamp = now()
    try pool.write { db in
      try db.execute(
        sql: "UPDATE stacks SET opened_at = ?, updated_at = ? WHERE id = ?",
        arguments: [stamp, stamp, id])
    }
  }

  /// The number of exports of every stack that has one.
  package func exportCounts() throws -> [Int64: Int] {
    try pool.read(Self.exportCounts(in:))
  }

  static func exportCounts(in db: Database) throws -> [Int64: Int] {
    try Row.fetchAll(db, sql: "SELECT stack_id, COUNT(*) AS n FROM exports GROUP BY stack_id")
      .reduce(into: [:]) { counts, row in counts[row["stack_id"]] = row["n"] }
  }

  /// The `project_settings` key of the stacks the user kept from the retention sheet.
  static let keptStacksKey = "retention.kept"

  /// Records stacks `ids` as kept: the retention policy never offers them again (card 0114).
  ///
  /// Kept in the project, so a renamed or moved project keeps the decision.
  package func keepStacks(_ ids: Set<Int64>) throws {
    let kept = Self.keptIDs(try setting(Self.keptStacksKey)).union(ids)
    try setSetting(Self.keptStacksKey, to: kept.sorted().map(String.init).joined(separator: ","))
  }

  /// The ids of a `retention.kept` value (comma-separated).
  static func keptIDs(_ value: String?) -> Set<Int64> {
    Set((value ?? "").split(separator: ",").compactMap { Int64($0) })
  }

  /// The folder of `bundlePath` when it is exactly `stacks/<name>`, else `nil`: the one guard
  /// that keeps a stack delete inside the package's `stacks/` (0113 leftovers use it too).
  package static func stackFolder(_ bundlePath: String, in package: URL) -> URL? {
    let parts = bundlePath.split(separator: "/", omittingEmptySubsequences: false)
    guard parts.count == 2, parts[0] == "stacks", !["", ".", ".."].contains(parts[1]) else {
      return nil
    }
    return package.appendingPathComponent(bundlePath, isDirectory: true)
  }

  static let storageLogger = Logger(
    subsystem: "fr.astrostack", category: "ProjectKit/storage")
}
