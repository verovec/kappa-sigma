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
