internal import Foundation

/// A Hough peak line: cos·x + sin·y = rho in pooled-grid coordinates.
struct HoughLine: Equatable {
  var cosine: Double
  var sine: Double
  var rho: Double
}

extension TrailSegmentDetector {
  /// The dominant line of the seeds and its votes; nil when it does not span or dominate.
  static func houghPeak(_ seeds: [Int], grid: Grid, voteFraction: Double) -> (
    line: HoughLine, votes: Int
  )? {
    let accumulator = HoughAccumulator(seeds, width: grid.width, height: grid.height)
    guard accumulator.accepts(voteFraction: voteFraction, width: grid.width, height: grid.height)
    else { return nil }
    return (accumulator.line, accumulator.peak)
  }
}
