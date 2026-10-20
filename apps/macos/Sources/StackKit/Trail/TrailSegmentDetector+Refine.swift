internal import Foundation

extension TrailSegmentDetector {
  /// A full-resolution swath sample and its background-subtracted flux weight.
  struct WeightedPoint {
    var x: Double
    var y: Double
    var weight: Double
  }

  /// The pooled line refined at full resolution (`refineSegment`): a flux-weighted principal-axis
  /// fit, a Gaussian width from the perpendicular profile, then the extent. Never fails: on
  /// degenerate weights the pooled line and a 2 px width stay.
  static func refine(
    _ plane: [Float], width: Int, height: Int, grid: Grid, inliers: [Int], line: HoughLine
  ) -> TrailSegment {
    var segment = TrailSegment(
      nx: line.cosine, ny: line.sine, c: line.rho * Double(grid.factor), width: 2)
    let background = PhotomStats.percentile(PhotomStats.subsample(plane, limit: 100_000), 50)
    let points = swath(
      plane, width: width, height: height, segment: segment, grid: grid, inliers: inliers,
      background: background)
    if points.count >= 8 {
      if let fitted = fitLine(points) { (segment.nx, segment.ny, segment.c) = fitted }
      segment.width = profileWidth(points, segment)
    }
    setExtent(&segment, grid: grid, inliers: inliers, width: width, height: height)
    return segment
  }

  /// The inliers' cell centres in full-resolution pixels.
  static func centres(_ inliers: [Int], grid: Grid) -> [(Double, Double)] {
    let half = Double(grid.factor) / 2
    return inliers.map {
      (
        Double(($0 % grid.width) * grid.factor) + half,
        Double(($0 / grid.width) * grid.factor) + half
      )
    }
  }

  /// Pixels within ⊥±8f of the pooled line and the inlier extent ±5%, weighted by v − background
  /// when positive (`gatherSwath`); only the band's bounding box is scanned.
  static func swath(
    _ plane: [Float], width: Int, height: Int, segment: TrailSegment, grid: Grid, inliers: [Int],
    background: Double
  ) -> [WeightedPoint] {
    let (dx, dy) = segment.direction
    let centres = centres(inliers, grid: grid)
    let along = centres.map { $0.0 * dx + $0.1 * dy }
    let (low, high) = (along.min() ?? 0, along.max() ?? 0)
    let xs = centres.map(\.0)
    let ys = centres.map(\.1)
    let band = 8.0 * Double(grid.factor)
    let (from, to) = (low - 0.05 * (high - low), high + 0.05 * (high - low))
    let x0 = clamp(Int((xs.min() ?? 0) - band), width)
    let x1 = clamp(Int((xs.max() ?? 0) + band), width)
    let y0 = clamp(Int((ys.min() ?? 0) - band), height)
    let y1 = clamp(Int((ys.max() ?? 0) + band), height)
    var points: [WeightedPoint] = []
    guard x0 <= x1, y0 <= y1 else { return points }
    for y in y0...y1 {
      for x in x0...x1 {
        let (fx, fy) = (Double(x), Double(y))
        guard abs(fx * segment.nx + fy * segment.ny - segment.c) <= band else { continue }
        let t = fx * dx + fy * dy
        guard t >= from && t <= to else { continue }
        let weight = Double(plane[y * width + x]) - background
        if weight > 0 { points.append(WeightedPoint(x: fx, y: fy, weight: weight)) }
      }
    }
    return points
  }

  /// The flux-weighted principal-axis line as (nx, ny, c); nil when the weight is zero.
  static func fitLine(_ points: [WeightedPoint]) -> (Double, Double, Double)? {
    var (total, sumX, sumY) = (0.0, 0.0, 0.0)
    for point in points {
      total += point.weight
      sumX += point.weight * point.x
      sumY += point.weight * point.y
    }
    guard total > 0 else { return nil }
    let (cx, cy) = (sumX / total, sumY / total)
    var (xx, yy, xy) = (0.0, 0.0, 0.0)
    for point in points {
      let (dx, dy) = (point.x - cx, point.y - cy)
      xx += point.weight * dx * dx
      yy += point.weight * dy * dy
      xy += point.weight * dx * dy
    }
    let phi = 0.5 * atan2(2 * xy, xx - yy)
    let (nx, ny) = (-sin(phi), cos(phi))
    return (nx, ny, nx * cx + ny * cy)
  }

  /// The Gaussian FWHM (2.355·σ⊥) of the flux-weighted perpendicular profile, at least 2 px.
  static func profileWidth(_ points: [WeightedPoint], _ segment: TrailSegment) -> Double {
    var (total, sum, squares) = (0.0, 0.0, 0.0)
    for point in points {
      let distance = segment.perpendicular(x: point.x, y: point.y)
      total += point.weight
      sum += point.weight * distance
      squares += point.weight * distance * distance
    }
    guard total > 0 else { return 2 }
    let mean = sum / total
    let variance = squares / total - mean * mean
    guard variance > 0 else { return 2 }
    return max(2, 2.355 * variance.squareRoot())
  }

  /// The masked extent (`setExtent`): to the image borders when the inliers span ≥ 60% of the
  /// short side, otherwise padded by min(0.15·short side, max(64, span / 2)).
  static func setExtent(
    _ segment: inout TrailSegment, grid: Grid, inliers: [Int], width: Int, height: Int
  ) {
    let (dx, dy) = segment.direction
    let along = centres(inliers, grid: grid).map { $0.0 * dx + $0.1 * dy }
    let (low, high) = (along.min() ?? 0, along.max() ?? 0)
    let shortSide = Double(min(width, height))
    let span = high - low
    if span >= 0.6 * shortSide, let border = segment.borderExtent(width: width, height: height) {
      (segment.t0, segment.t1) = border
      return
    }
    let pad = min(0.15 * shortSide, max(64, 0.5 * span))
    (segment.t0, segment.t1) = (low - pad, high + pad)
  }

  private static func clamp(_ value: Int, _ size: Int) -> Int { min(max(value, 0), size - 1) }
}
