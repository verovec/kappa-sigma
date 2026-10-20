internal import Foundation

/// A satellite or aircraft trail in a downsampled, max-pooled frame (`grade.DetectTrail`).
///
/// A Hough line transform over the bright cells. A streak gives one bin that both spans much of the
/// frame and dominates every other; stars spread their votes.
package enum TrailDetector {
  /// Bright cells: above median + k·σ.
  static let brightSigma = 5.0
  /// One-degree angular resolution.
  static let angles = 180
  /// A frame with more bright cells than this fraction is texture, not a streak.
  static let maxBrightFraction = 0.30
  /// The peak line must span this fraction of the short side.
  package static let voteFraction = 0.25
  /// The peak must outvote the 99th percentile of busy bins this many times.
  static let peakRatio = 4.0

  /// Whether `grid` (`width` × `height`) holds a trail, and the span score (peak ÷ short side).
  package static func detect(_ grid: [Double], width: Int, height: Int) -> (
    detected: Bool, score: Double
  ) {
    guard width >= 16, height >= 16, grid.count == width * height else { return (false, 0) }
    let (median, rawMAD) = Robust.medianMAD(grid)
    let mad = 1.4826 * rawMAD
    guard mad > 0 else { return (false, 0) }
    let threshold = median + brightSigma * mad
    let bright = grid.indices.filter { grid[$0] > threshold }
    guard bright.count >= 16, Double(bright.count) <= maxBrightFraction * Double(width * height)
    else {
      return (false, 0)
    }
    let hough = HoughAccumulator(bright, width: width, height: height)
    let score = Double(hough.peak) / Double(min(width, height))
    return (score >= voteFraction && Double(hough.peak) >= peakRatio * hough.percentile99, score)
  }
}
