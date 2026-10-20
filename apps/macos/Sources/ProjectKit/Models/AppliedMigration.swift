/// A row of `schema_migrations`: a migration applied to this database.
package struct AppliedMigration: Equatable, Sendable {
  /// The migration's version.
  package let version: Int
  /// The migration's name.
  package let name: String
  /// When it was applied, Unix milliseconds.
  package let appliedAtMs: Int64
}
