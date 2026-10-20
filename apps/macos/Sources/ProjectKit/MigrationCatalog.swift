package import Foundation
internal import ImageKit

/// Reads the migrations shipped in `Migrations/` (ProjectKit resources).
package enum MigrationCatalog {
  /// SwiftPM's resource bundle for ProjectKit (`<package>_<target>.bundle`).
  private static let bundleName = "AstroStack_ProjectKit.bundle"

  /// The migrations bundled with ProjectKit, by version.
  package static func bundled() throws -> [Migration] {
    let bundle = resourceBundle()
    let folder =
      bundle.url(forResource: "Migrations", withExtension: nil)
      ?? bundle.bundleURL.appendingPathComponent("Migrations")
    return try load(from: folder)
  }

  /// The migrations in `folder`; a missing or unreadable folder is an error, never empty.
  package static func load(from folder: URL) throws -> [Migration] {
    let names: [String]
    do {
      names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
    } catch {
      throw MigrationError.catalogMissing(path: folder.path)
    }
    var files: [String: String] = [:]
    for name in names where name.hasSuffix(".sql") {
      files[name] = try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
    }
    return try parse(files: files)
  }

  /// ProjectKit's resources, in the packaged app or in tests (`KitBundle`).
  private static func resourceBundle() -> Bundle {
    KitBundle.resolve(named: bundleName) { Bundle.module }
  }

  /// Pairs `NNNN_name.up.sql` with `NNNN_name.down.sql` (file name → SQL), sorted by version,
  /// refusing bad names, unpaired files, duplicate versions and holes.
  package static func parse(files: [String: String]) throws -> [Migration] {
    var ups: [Int: (name: String, sql: String)] = [:]
    var downs: [Int: (name: String, sql: String)] = [:]
    for file in files.keys.sorted() {
      let (version, name, isUp) = try split(file)
      if isUp {
        guard ups[version].map({ $0.name == name }) ?? true else {
          throw MigrationError.duplicateVersion(version)
        }
        ups[version] = (name, files[file] ?? "")
      } else {
        guard downs[version].map({ $0.name == name }) ?? true else {
          throw MigrationError.duplicateVersion(version)
        }
        downs[version] = (name, files[file] ?? "")
      }
    }
    var migrations: [Migration] = []
    for version in Set(ups.keys).union(downs.keys).sorted() {
      guard let up = ups[version], let down = downs[version], up.name == down.name else {
        throw MigrationError.unpaired(version: version)
      }
      guard version == migrations.count + 1 else {
        throw MigrationError.gap(after: migrations.count)
      }
      migrations.append(Migration(version: version, name: up.name, up: up.sql, down: down.sql))
    }
    return migrations
  }

  /// `NNNN_name.up.sql` → (NNNN, name, true).
  private static func split(_ file: String) throws -> (Int, String, Bool) {
    let isUp = file.hasSuffix(".up.sql")
    guard isUp || file.hasSuffix(".down.sql") else { throw MigrationError.badFileName(file) }
    let stem = file.dropLast(isUp ? 7 : 9)
    let parts = stem.split(separator: "_", maxSplits: 1)
    guard parts.count == 2, parts[0].count == 4, let version = Int(parts[0]), version >= 1,
      parts[1].allSatisfy({ $0.isLowercase || $0.isNumber || $0 == "_" })
    else { throw MigrationError.badFileName(file) }
    return (version, String(parts[1]), isUp)
  }
}
