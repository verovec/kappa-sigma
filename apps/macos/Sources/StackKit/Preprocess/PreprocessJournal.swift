/// A run's warnings and its live journal (`Result.Warnings` + `warnLive`): every warning is
/// recorded; a live one is also surfaced (`⚠`-prefixed) the moment it happens.
package struct PreprocessJournal: Sendable {
  package private(set) var warnings: [String] = []
  /// Where live lines go.
  let report: @Sendable (String) -> Void

  /// A journal reporting live lines to `report`.
  package init(report: @escaping @Sendable (String) -> Void = { _ in }) {
    self.report = report
  }

  /// Records `message`; `live` also surfaces it now.
  mutating func warn(_ message: String, live: Bool = true) {
    warnings.append(message)
    if live { report("⚠ " + message) }
  }

  /// A progress line, not a warning.
  func line(_ text: String) { report(text) }
}
