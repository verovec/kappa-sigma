/// Why a plate solve gave no solution, in words the user can act on.
package enum PlateSolveError: Error, Equatable, Sendable {
  /// Siril found no solution: its own line (never retried with other settings).
  case failed(reason: String)
  /// The local catalogue is not on disk (`just download-catalogues`); nothing went online.
  case catalogueMissing(path: String)
  /// Siril said it solved but wrote no readable TAN solution.
  case noSolution(path: String)
}
