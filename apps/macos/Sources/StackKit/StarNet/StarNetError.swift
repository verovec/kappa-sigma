/// Why StarNet could not make a starless image.
package enum StarNetError: Error, Equatable, Sendable {
  /// No usable StarNet at `path` (`HostTools`): the process is greyed with an install card, never
  /// replaced by another star removal (R2).
  case missing(path: String)
  /// StarNet is installed at `path` but this Mac cannot launch it (`reason`: an Intel build
  /// without Rosetta): greyed like a missing tool, with what to install.
  case cannotRun(path: String, reason: String)
  /// `--machine-info` did not answer in time, so the command line is unknown.
  case probeTimedOut(path: String)
  /// StarNet exited with `exitCode`; `log` is what it printed.
  case failed(exitCode: Int32, log: String)
  /// StarNet exited cleanly but wrote nothing at `path`.
  case noOutput(path: String)
}
