/// A channel's trail-mask outcome as `run.json` recorded it (`transient.Summary`).
package struct TrailMaskSummary: Codable, Equatable, Sendable {
  package var frames = 0
  package var framesWithTrails = 0
  package var segments = 0
  package var maskedPixels = 0
  package var rejected = 0
  package var geostationary = 0
  package var recurring = 0
  /// Sensor-saturated core pixels repaired from unsaturated nights (`SaturationRepair`).
  package var saturatedPixels = 0

  /// A summary.
  package init(
    frames: Int = 0, framesWithTrails: Int = 0, segments: Int = 0, maskedPixels: Int = 0,
    rejected: Int = 0, geostationary: Int = 0, recurring: Int = 0
  ) {
    self.frames = frames
    self.framesWithTrails = framesWithTrails
    self.segments = segments
    self.maskedPixels = maskedPixels
    self.rejected = rejected
    self.geostationary = geostationary
    self.recurring = recurring
  }

  enum CodingKeys: String, CodingKey {
    case frames, segments, recurring
    case framesWithTrails = "frames_with_trails"
    case maskedPixels = "masked_px"
    case rejected = "rejected_fixed_pattern"
    case geostationary = "geostationary_segments"
    case saturatedPixels = "sat_masked_px"
  }
}
