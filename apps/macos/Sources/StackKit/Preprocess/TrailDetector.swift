internal import Foundation

/// A satellite or aircraft trail in a downsampled, max-pooled frame (`grade.DetectTrail`): a Hough
/// line transform over the bright cells. A streak gives one bin that both spans much of the
/// frame and dominates every other; stars spread their votes.
package enum TrailDetector {
  /// Bright cells: above median + k·σ.
  static let brightSigma = 5.0
  /// One-degree angular resolution.
  static let angles = 180
  /// A frame with more bright cells than this fraction is texture, not a streak.
  static let maxBrightFraction = 0.30
  /// The peak line must span this fraction of the short side…
  package static let voteFraction = 0.25
  /// …and outvote the 99th percentile of busy bins this many times.
  static let peakRatio = 4.0

  /// Whether `grid` (`width` × `height`) holds a trail, and the span score (peak ÷ short side).
  package static func detect(_ grid: [Double], width: Int, height: Int) -> (detected: Bool, score: Double) {
    guard width >= 16, height >= 16, grid.count == width * height else { return (false, 0) }
    let (median, rawMAD) = Robust.medianMAD(grid)
    let mad = 1.4826 * rawMAD
    guard mad > 0 else { return (false, 0) }
    let threshold = median + brightSigma * mad
    let bright = grid.indices.filter { grid[$0] > threshold }
    guard bright.count >= 16, Double(bright.count) <= maxBrightFraction * Double(width * height) else {
      return (false, 0)
    }
    let diagonal = Int(Double(width).hypot(Double(height)).rounded(.up))
    let bins = 2 * diagonal + 1
    var votes = [Int](repeating: 0, count: angles * bins)
    var peak = 0
    let trig = (0..<angles).map { angle -> (Double, Double) in
      let radians = Double.pi * Double(angle) / Double(angles)
      return (cos(radians), sin(radians))
    }
    for cell in bright {
      let (x, y) = (Double(cell % width), Double(cell / width))
      for (angle, (cosine, sine)) in trig.enumerated() {
        let index = angle * bins + Int((x * cosine + y * sine).rounded()) + diagonal
        votes[index] += 1
        peak = max(peak, votes[index])
      }
    }
    let score = Double(peak) / Double(min(width, height))
    return (score >= voteFraction && Double(peak) >= peakRatio * percentile99(votes), score)
  }

  /// The 99th-percentile vote among non-empty bins.
  private static func percentile99(_ votes: [Int]) -> Double {
    let positive = votes.filter { $0 > 0 }.sorted()
    guard !positive.isEmpty else { return 0 }
    return Double(positive[Int(0.99 * Double(positive.count - 1))])
  }
}

extension Double {
  /// √(self² + other²), as `math.Hypot`.
  fileprivate func hypot(_ other: Double) -> Double { Foundation.hypot(self, other) }
}
