/// The kind of a capture frame (`internal/inspect/types.go`); raw values are the legacy wire names.
package enum FrameType: String, CaseIterable, Codable, Sendable {
  case light = "LIGHT"
  case dark = "DARK"
  case flat = "FLAT"
  case bias = "BIAS"
  case darkFlat = "DARKFLAT"
  case video = "VIDEO"
  case unknown = "UNKNOWN"

  /// Calibration or video: never named by a light's wheel legend or manifest.
  package var isCalibration: Bool { [.dark, .flat, .bias, .darkFlat, .video].contains(self) }

  /// Grouped without a filter (darks, bias, dark-flats, video); flats and lights are per filter.
  package var isFilterAgnostic: Bool { [.dark, .bias, .darkFlat, .video].contains(self) }

  /// Whether a set of this type is split by sensor temperature (a thermal signature).
  package var usesTemperature: Bool { [.light, .dark, .darkFlat].contains(self) }

  /// Display and sort order of sets (`typeOrder`); types never grouped sort first, as in Go.
  var setOrder: Int {
    switch self {
    case .dark: 1
    case .flat: 2
    case .darkFlat: 3
    case .bias: 4
    case .light, .video, .unknown: 0
    }
  }
}

/// How a frame's type (or filter) was decided.
package enum ClassSource: String, Codable, Sendable {
  /// Nothing has decided yet.
  case none = ""
  /// The FITS IMAGETYP card.
  case header
  /// The file or folder name.
  case filename
  /// The pixel curve.
  case heuristic
  /// The file extension (videos).
  case fileExtension = "extension"
  /// The filter was inferred from the signal by wheel-order detection.
  case signal
  /// The filter was set by a user override.
  case manual
  /// The filter came from an `info.txt` manifest.
  case manifest
  /// The filter was named from the physical wheel slot.
  case wheel
}
