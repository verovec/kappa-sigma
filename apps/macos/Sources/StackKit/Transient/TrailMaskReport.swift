/// What the cross-frame trail mask changed (`transient.Report`).
package struct TrailMaskReport: Equatable, Sendable {
  /// One frame's changes (1-based `index`).
  package struct Frame: Equatable, Sendable {
    package var index: Int
    package var segments = 0
    package var maskedPixels = 0
  }

  package var frames: [Frame] = []
  /// Line candidates rejected as fixed pattern (walking noise).
  package var rejected = 0
  /// Streaks present in the cross-frame median, repaired from the local sky.
  package var geostationary = 0
  /// Reused sky tracks found on the mean residual and repaired.
  package var recurring = 0

  /// The compact record.
  package var summary: TrailMaskSummary {
    TrailMaskSummary(
      frames: frames.count, framesWithTrails: frames.filter { $0.maskedPixels > 0 }.count,
      segments: frames.reduce(0) { $0 + $1.segments },
      maskedPixels: frames.reduce(0) { $0 + $1.maskedPixels }, rejected: rejected,
      geostationary: geostationary, recurring: recurring)
  }
}

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

  enum CodingKeys: String, CodingKey {
    case frames, segments, recurring
    case framesWithTrails = "frames_with_trails"
    case maskedPixels = "masked_px"
    case rejected = "rejected_fixed_pattern"
    case geostationary = "geostationary_segments"
    case saturatedPixels = "sat_masked_px"
  }
}

/// Why the mask could not run.
package enum TrailMaskError: Error, Equatable, Sendable {
  /// Frame `index` does not have the first frame's planes and size (registered frames must).
  case mismatchedFrame(index: Int)
}
