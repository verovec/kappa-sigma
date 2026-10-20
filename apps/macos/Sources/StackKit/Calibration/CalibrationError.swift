/// Why a calibration step failed, with what the user can act on.
package enum CalibrationError: Error, Equatable, Sendable {
  /// The library folder does not exist or cannot be listed.
  case unreadableLibrary(String)
  /// Siril could not stack a master; the set is reported and skipped.
  case masterFailed(name: String, reason: String)
}
