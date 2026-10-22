/// Why GraXpert could not extract a background.
package enum GraXpertError: Error, Equatable, Sendable {
  /// No `GraXpert.app` at `path` (`HostTools`): the engine is greyed with an install card, never
  /// replaced by a Siril engine (R2).
  case missing(path: String)
  /// GraXpert exited with `exitCode` (nil: a signal); `log` is what it printed.
  case failed(exitCode: Int32?, log: String)
  /// GraXpert exited cleanly but logged `line`, a `Critical error` (a broken AI runtime exits 0).
  case reportedError(line: String)
  /// GraXpert exited cleanly but wrote nothing at `path`.
  case noOutput(path: String)
  /// GraXpert was still running after `after` and was stopped.
  case timedOut(after: Duration)
}
