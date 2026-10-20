internal import Foundation

/// The shared 180-bin Hough accumulator of `grade.DetectTrail` and `trail.houghPeak`: ρ binned as
/// round(x·cos + y·sin) + diag, diag = ⌈hypot(w, h)⌉, the first strictly highest bin kept.
struct HoughAccumulator {
  var votes: [Int]
  var peak = 0
  var line = HoughLine(cosine: 1, sine: 0, rho: 0)

  /// Votes of the `cells` (indices into a `width`-wide grid).
  init(_ cells: [Int], width: Int, height: Int) {
    let angles = TrailDetector.angles
    let trig = (0..<angles).map { angle -> (Double, Double) in
      let radians = Double.pi * Double(angle) / Double(angles)
      return (cos(radians), sin(radians))
    }
    let diagonal = Int(hypot(Double(width), Double(height)).rounded(.up))
    let bins = 2 * diagonal + 1
    votes = [Int](repeating: 0, count: angles * bins)
    var (bestAngle, bestRho) = (0, 0)
    for cell in cells {
      let (x, y) = (Double(cell % width), Double(cell / width))
      for (angle, (cosine, sine)) in trig.enumerated() {
        let rho = Int((x * cosine + y * sine).rounded()) + diagonal
        let index = angle * bins + rho
        votes[index] += 1
        if votes[index] > peak { (peak, bestAngle, bestRho) = (votes[index], angle, rho) }
      }
    }
    line = HoughLine(
      cosine: trig[bestAngle].0, sine: trig[bestAngle].1, rho: Double(bestRho - diagonal))
  }

  /// The peak spans `fraction` of the short side and outvotes the 99th percentile of busy bins
  /// `TrailDetector.peakRatio` times.
  func accepts(voteFraction fraction: Double, width: Int, height: Int) -> Bool {
    Double(peak) >= fraction * Double(min(width, height))
      && Double(peak) >= TrailDetector.peakRatio * percentile99
  }

  /// The 99th-percentile vote among non-empty bins.
  var percentile99: Double {
    let positive = votes.filter { $0 > 0 }.sorted()
    guard !positive.isEmpty else { return 0 }
    return Double(positive[Int(0.99 * Double(positive.count - 1))])
  }
}
