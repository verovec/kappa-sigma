/// Why the migration catalog or a migration run was refused.
package enum MigrationError: Error, Equatable, Sendable {
  /// A file in `Migrations/` is not `NNNN_name.up.sql` / `.down.sql` with NNNN ≥ 1.
  case badFileName(String)
  /// A version has an up without a down, or a down without an up.
  case unpaired(version: Int)
  /// Two migrations share a version.
  case duplicateVersion(Int)
  /// Versions must run 1, 2, 3… without holes.
  case gap(after: Int)
  /// The database records a version this build does not know (a newer app wrote it).
  case unknownVersion(Int)
  /// The requested target version is not in the catalog.
  case unknownTarget(Int)
  /// The bundled `Migrations/` folder cannot be found or read: a broken build, not a project.
  case catalogMissing(path: String)
  /// The database applied `version` under another name than the catalog's.
  case nameMismatch(version: Int, applied: String, catalog: String)
  /// `version` is not applied although the later `applied` is: the history has a hole.
  case missingBelow(version: Int, applied: Int)
}
