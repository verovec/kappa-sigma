/// The masters chosen for one light set, with the notes that explain every gap and fallback
/// (`calib.Selection`).
package struct CalibrationSelection: Equatable, Sendable {
  package var dark: CalibrationMaster?
  package var flat: CalibrationMaster?
  package var bias: CalibrationMaster?
  package var notes: [String] = []
  /// `dark` has another exposure and is scaled onto the light by Siril (`-opt`); always with a bias.
  package var darkOptimize = false

  /// What `calibrate` applies.
  package var masters: CalibrationMasters {
    CalibrationMasters(
      bias: bias?.path, dark: dark?.path, flat: flat?.path, darkOptimize: darkOptimize)
  }

  func master(_ role: CalibrationRole) -> CalibrationMaster? {
    switch role {
    case .dark: dark
    case .flat: flat
    case .bias: bias
    }
  }
}
