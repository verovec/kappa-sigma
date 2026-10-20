/// One schema migration: `Migrations/NNNN_name.up.sql` and its `.down.sql`.
package struct Migration: Equatable, Sendable {
  /// The 1-based version (`NNNN`).
  package let version: Int
  /// The name after the version (`init`).
  package let name: String
  /// SQL applied when migrating up.
  package let up: String
  /// SQL that undoes `up`.
  package let down: String

  /// A migration; versions start at 1.
  package init(version: Int, name: String, up: String, down: String) {
    self.version = version
    self.name = name
    self.up = up
    self.down = down
  }
}
