/// What the cross-frame trail mask changed (`transient.Report`).
package struct TrailMaskReport: Equatable, Sendable {
  /// One frame's changes (1-based `index`).
  package struct Frame: Equatable, Sendable {
    package var index: Int
    package var segments = 0
    package var maskedPixels = 0
    /// Line candidates rejected as fixed pattern (walking noise).
    package var rejected = 0
  }

  package var frames: [Frame] = []
  /// Streaks present in the cross-frame median, repaired from the local sky.
  package var geostationary = 0
  /// Reused sky tracks found on the mean residual and repaired.
  package var recurring = 0

  /// The compact record.
  package var summary: TrailMaskSummary {
    TrailMaskSummary(
      frames: frames.count, framesWithTrails: frames.filter { $0.maskedPixels > 0 }.count,
      segments: frames.reduce(0) { $0 + $1.segments },
      maskedPixels: frames.reduce(0) { $0 + $1.maskedPixels },
      rejected: frames.reduce(0) { $0 + $1.rejected },
      geostationary: geostationary, recurring: recurring)
  }
}
