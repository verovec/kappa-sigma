/// Why a plate solve gave no solution, in words the user can act on.
package enum PlateSolveError: Error, Equatable, Sendable {
  /// Siril found no solution: its own line (never retried with other settings).
  case failed(reason: String)
  /// The local catalogue is not on disk (`just download-catalogues`); nothing went online.
  case catalogueMissing(path: String)
  /// Siril ended without the lines of a solution (centre, scale, rotation): the last lines
  /// `platesolve` printed, and where its whole log is kept.
  case noReport(lastLines: String, log: String)
  /// Siril said it solved, but its centre, scale or rotation could not be read.
  case reportUnread(log: String)
  /// Siril reported a solution but wrote no file.
  case noFile(log: String)
  /// Siril wrote a file that cannot be read.
  case unreadableFile(log: String)
  /// Siril wrote the file without a readable TAN solution.
  case noSolution(log: String)
}
