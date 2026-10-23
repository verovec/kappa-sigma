/// Why a plate solve gave no solution, in words the user can act on.
package enum PlateSolveError: Error, Equatable, Sendable {
  /// Siril found no solution: its own line (never retried with other settings).
  case failed(reason: String)
  /// The local catalogue is not on disk (`just download-catalogues`); nothing went online.
  case catalogueMissing(path: String)
  /// Siril ended without the lines of a solution (centre, scale, rotation): its last lines.
  case noReport(lastLines: String)
  /// Siril reported a solution but wrote no file.
  case noFile(path: String)
  /// Siril wrote the file without a readable TAN solution.
  case noSolution(path: String)
}
