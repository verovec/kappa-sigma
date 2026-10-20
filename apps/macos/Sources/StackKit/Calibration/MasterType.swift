/// The kind of a master calibration frame (`calib.MasterType`); raw values are the legacy names.
package enum MasterType: String, CaseIterable, Codable, Sendable {
  case bias = "BIAS"
  case dark = "DARK"
  case flat = "FLAT"
  case darkFlat = "DARKFLAT"

  /// The master a calibration frame type builds; `nil` for lights, videos, unknown.
  package init?(_ frameType: FrameType) {
    switch frameType {
    case .bias: self = .bias
    case .dark: self = .dark
    case .flat: self = .flat
    case .darkFlat: self = .darkFlat
    case .light, .video, .unknown: return nil
    }
  }

  /// The frame type this master is built from.
  package var frameType: FrameType {
    switch self {
    case .bias: .bias
    case .dark: .dark
    case .flat: .flat
    case .darkFlat: .darkFlat
    }
  }

  /// Darks and dark-flats are thermal signatures, matched on sensor temperature.
  package var isThermal: Bool { self == .dark || self == .darkFlat }

  /// Build order: bias and dark-flats first (flats are calibrated with them), flats last.
  package static let buildOrder: [Self] = [.bias, .darkFlat, .dark, .flat]
}

/// A role a master fills for a light (`RoleDark`/`RoleFlat`/`RoleBias`).
package enum CalibrationRole: String, CaseIterable, Sendable {
  case dark
  case flat
  case bias
}
