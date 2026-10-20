internal import Accelerate
internal import Foundation

/// Finds up to four straight satellite or aircraft trails in a full-resolution plane
/// (`trail.DetectSegments`).
///
/// The plane is max-pooled to ≤ 1024 px; a Hough transform over robustly bright seed cells finds
/// the dominant line; an elongated connected component confirms it; the line, width and extent
/// are refined at full resolution. The streak is then erased from the pooled grid and the pass
/// repeats. The Hough tuning is `TrailDetector`'s (the grading probe). Degenerate input yields
/// nothing; nothing traps.
package enum TrailSegmentDetector {
  /// The seed-threshold regime.
  package enum Mode: Sendable {
    /// Median-subtracted planes: a flat sky, a trail a few σ above it.
    case residual
    /// Raw light frames full of stars: seeds at 5σ so stars do not flood the accumulator.
    case raw
  }

  /// One pass's tuning (`trail.Params`).
  package struct Params: Sendable {
    package var mode: Mode
    /// Scales the residual-mode seed threshold; raw mode ignores it.
    package var k: Double
    /// How much of the pooled grid's short side a line must span; ≤ 0 keeps 0.25.
    package var voteFraction: Double
    /// The raw-mode seed threshold in σ; ≤ 0 keeps 5.
    package var rawSeedK: Double

    /// A pass.
    package init(mode: Mode, k: Double, voteFraction: Double = 0, rawSeedK: Double = 0) {
      self.mode = mode
      self.k = k
      self.voteFraction = voteFraction
      self.rawSeedK = rawSeedK
    }

    /// Residual-mode parameters (`DefaultParams`).
    package static func residual(k: Double) -> Self { Self(mode: .residual, k: k) }

    /// Raw-mode parameters (`RawParams`).
    package static func raw(k: Double) -> Self { Self(mode: .raw, k: k) }

    /// The span requirement this pass uses.
    package var effectiveVoteFraction: Double {
      voteFraction > 0 ? voteFraction : TrailDetector.voteFraction
    }

    /// The seed multiplier: residual clamps 0.7·k to [1.5, 2.5]; raw is 5σ unless overridden.
    package var seedK: Double {
      switch mode {
      case .raw: rawSeedK > 0 ? rawSeedK : TrailDetector.brightSigma
      case .residual: min(max(0.7 * k, 1.5), 2.5)
      }
    }
  }

  /// The pooled grid the Hough pass runs on.
  struct Grid {
    var cells: [Double]
    var width: Int
    var height: Int
    /// Full-resolution pixels per cell side.
    var factor: Int
  }

  /// The plane's trails, at most four.
  package static func detect(_ plane: [Float], width: Int, height: Int, params: Params)
    -> [TrailSegment]
  {
    guard width >= 32, height >= 32, plane.count == width * height else { return [] }
    var grid = maxPool(plane, width: width, height: height)
    guard grid.width >= 16, grid.height >= 16 else { return [] }
    var segments: [TrailSegment] = []
    while segments.count < 4,
      let segment = detectOne(&grid, plane: plane, width: width, height: height, params: params)
    {
      segments.append(segment)
    }
    return segments
  }

  /// One pass over the (partly erased) grid; on success the streak's band is erased.
  static func detectOne(
    _ grid: inout Grid, plane: [Float], width: Int, height: Int, params: Params
  ) -> TrailSegment? {
    let (median, sigma) = robustStats(grid.cells)
    guard sigma > 0 else { return nil }
    let threshold = median + params.seedK * sigma
    let seeds = grid.cells.indices.filter { grid.cells[$0] > threshold }
    guard seeds.count >= 16,
      Double(seeds.count) <= TrailDetector.maxBrightFraction * Double(grid.cells.count),
      let peak = houghPeak(seeds, grid: grid, voteFraction: params.effectiveVoteFraction),
      let inliers = confirmInliers(seeds, grid: grid, line: peak.line)
    else { return nil }
    var segment = refine(
      plane, width: width, height: height, grid: grid, inliers: inliers, line: peak.line)
    segment.score = Double(peak.votes) / Double(min(grid.width, grid.height))
    eraseBand(&grid, line: peak.line, inliers: inliers, median: median)
    return segment
  }

  /// Sets every cell within ⊥4 of the line and inside the inlier extent (±4) to the median.
  static func eraseBand(_ grid: inout Grid, line: HoughLine, inliers: [Int], median: Double) {
    let (dx, dy) = (-line.sine, line.cosine)
    let along = inliers.map { Double($0 % grid.width) * dx + Double($0 / grid.width) * dy }
    let half = 4.0
    let (low, high) = ((along.min() ?? 0) - half, (along.max() ?? 0) + half)
    for gy in 0..<grid.height {
      for gx in 0..<grid.width {
        let (x, y) = (Double(gx), Double(gy))
        guard abs(x * line.cosine + y * line.sine - line.rho) <= half else { continue }
        let t = x * dx + y * dy
        if t >= low && t <= high { grid.cells[gy * grid.width + gx] = median }
      }
    }
  }

  /// Max-pools the plane until both sides are ≤ 1024 cells, preserving thin streaks.
  static func maxPool(_ plane: [Float], width: Int, height: Int) -> Grid {
    var factor = 1
    while (width + factor - 1) / factor > 1024 || (height + factor - 1) / factor > 1024 {
      factor += 1
    }
    let (gridWidth, gridHeight) = ((width + factor - 1) / factor, (height + factor - 1) / factor)
    var cells = [Double](repeating: -.infinity, count: gridWidth * gridHeight)
    for y in 0..<height {
      let (row, base) = ((y / factor) * gridWidth, y * width)
      for x in 0..<width {
        let value = Double(plane[base + x])
        if value > cells[row + x / factor] { cells[row + x / factor] = value }
      }
    }
    for index in cells.indices where cells[index] == -.infinity { cells[index] = 0 }
    return Grid(cells: cells, width: gridWidth, height: gridHeight, factor: factor)
  }

  /// The upper median and 1.4826 × the upper-median absolute deviation (`robustStats`, `medMAD`).
  static func robustStats(_ values: [Double]) -> (median: Double, sigma: Double) {
    guard !values.isEmpty else { return (0, 0) }
    var sorted = values
    vDSP.sort(&sorted, sortOrder: .ascending)
    let median = sorted[sorted.count / 2]
    var deviations = sorted.map { abs($0 - median) }
    vDSP.sort(&deviations, sortOrder: .ascending)
    return (median, 1.4826 * deviations[deviations.count / 2])
  }
}
