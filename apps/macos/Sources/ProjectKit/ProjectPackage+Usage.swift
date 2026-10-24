package import Foundation
internal import GRDB

extension ProjectPackage {
  /// The stacks, export counts, chosen stack (`chosenKey` of `project_settings`) and kept stacks of the
  /// package at `url`, read-only (card 0114); `nil` for a package written before 0008, whose
  /// last openings are unknown: it offers nothing until the app opens it once.
  package static func readUsage(at url: URL, chosenKey: String) throws -> StackUsage? {
    try readOnly(at: url) { db in
      guard try db.columns(in: "stacks").contains(where: { $0.name == "opened_at" }) else {
        return nil
      }
      let stacks = try Row.fetchAll(db, sql: "SELECT * FROM stacks ORDER BY id")
        .map { try ProjectStore.stack($0, in: db) }
      let counts = try ProjectStore.exportCounts(in: db)
      func setting(_ key: String) throws -> String? { try ProjectStore.setting(key, in: db) }
      return StackUsage(
        stacks: stacks, exportCounts: counts,
        chosenStackID: try setting(chosenKey).flatMap(Int64.init),
        keptStackIDs: ProjectStore.keptIDs(try setting(ProjectStore.keptStacksKey)),
        since: try Int64.fetchOne(
          db, sql: "SELECT applied_at FROM schema_migrations WHERE version = 8") ?? 0)
    }
  }
}
