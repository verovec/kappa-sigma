/// Where a project's pixels come from, referenced by path and never written (R7).
package struct ProjectSource: Equatable, Sendable {
  /// What the path points to.
  package enum Kind: String, Sendable {
    /// An imported capture night (`~/Documents/astro/captures/…`).
    case night
    /// A legacy run folder (`~/Documents/astro/runs/…`).
    case legacyRun = "legacy_run"
  }

  /// Row id.
  package let id: Int64
  /// What the path points to.
  package let kind: Kind
  /// Absolute path of the source folder.
  package let path: String
  /// Always true today: the app never writes into a source.
  package let readOnly: Bool
  /// Creation time, Unix milliseconds.
  package let createdAt: Int64
  /// Last update time, Unix milliseconds.
  package let updatedAt: Int64
}
