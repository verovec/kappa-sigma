/// The colour a line layer is screened in: `out_c = base_c + α · line · tint_c · (1 − base_c)`.
package enum ScreenTint: String, CaseIterable, Sendable {
  /// Pure red: astrocomp's Hα.
  case red
  /// Green + blue: astrocomp's [OIII].
  case teal
  /// A blue-leaning red (CSS crimson).
  case crimson
  /// A warm yellow (CSS gold).
  case gold
  /// Pure green.
  case green
  /// Pure blue.
  case blue

  /// The tint's red, green and blue weights.
  package var rgb: [Double] {
    switch self {
    case .red: [1, 0, 0]
    case .teal: [0, 1, 1]
    case .crimson: [220.0 / 255, 20.0 / 255, 60.0 / 255]
    case .gold: [1, 215.0 / 255, 0]
    case .green: [0, 1, 0]
    case .blue: [0, 0, 1]
    }
  }
}
