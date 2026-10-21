/// A row of `project_settings`: one per-project value a window restores, by key.
package struct ProjectSetting: Equatable, Sendable {
  /// Row id.
  package var id: Int64
  /// The setting's name (`workspace.stage`).
  package var key: String
  /// Its value, as text.
  package var value: String
  /// Unix milliseconds of the first write.
  package var createdAtMs: Int64
  /// Unix milliseconds of the last write.
  package var updatedAtMs: Int64
}
