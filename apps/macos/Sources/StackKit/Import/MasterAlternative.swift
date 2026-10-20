/// A library master a role could take instead (the Import sheet's "Use another…"), with the
/// matcher's own verdict on it: the app adds no rule of its own.
package struct MasterAlternative: Equatable, Sendable, Identifiable {
  /// What the matcher makes of this master for this light set.
  package enum Verdict: Equatable, Sendable {
    /// The one the plan applies.
    case chosen
    /// Matches strictly; it loses only on rank (temperature, night, depth).
    case matches
    /// Applied only with `force_calibration_frames`: gain, exposure or temperature differs.
    case needsForce
    /// Another sensor: never applied, even forced (the dimension guard's note).
    case otherSensor(String)
  }

  package var master: CalibrationMaster
  package var verdict: Verdict
  package var id: String { master.path }
}
