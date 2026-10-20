/// Why a calibration step failed, with what the user can act on.
package enum CalibrationError: Error, Equatable, Sendable {
  /// The library folder does not exist or cannot be listed.
  case unreadableLibrary(String)
  /// Siril could not stack a master; the set is reported and skipped.
  case masterFailed(name: String, reason: String)
  /// A file whose name is not a master's (`MasterName`): nothing to inspect.
  case notAMaster(String)
  /// A rebuild would overwrite this library master (stacked from `frames` frames, 0 = unknown):
  /// the user must agree first.
  case wouldReplace(path: String, frames: Int)
  /// A master whose pixels cannot be measured (no plane, or planes of the wrong size).
  case unreadableMaster(String)
}
