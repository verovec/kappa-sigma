internal import Foundation

/// One detected trail (`trail.Segment`): the line n·p = rho in full-resolution pixels (n = (nx, ny)
/// a unit normal), masked over t ∈ [t0, t1] along the direction (−ny, nx), with a Gaussian full
/// width `width` (px, FWHM). `score` is the Hough span confidence.
package struct TrailSegment: Equatable, Sendable {
  package var nx: Double
  package var ny: Double
  package var rho: Double
  package var t0: Double
  package var t1: Double
  package var width: Double
  package var score: Double

  /// The swath covers ±`dilate`·width/2 = ±width of the line.
  static let dilate = 2.0

  /// A segment.
  package init(
    nx: Double, ny: Double, rho: Double, t0: Double = 0, t1: Double = 0, width: Double = 2,
    score: Double = 0
  ) {
    self.nx = nx
    self.ny = ny
    self.rho = rho
    self.t0 = t0
    self.t1 = t1
    self.width = width
    self.score = score
  }

  /// The unit direction along the line.
  package var direction: (Double, Double) { (-ny, nx) }

  /// The signed perpendicular distance of (x, y) from the line.
  func perpendicular(x: Double, y: Double) -> Double { nx * x + ny * y - rho }

  /// The coordinate of (x, y) along the line.
  package func project(x: Double, y: Double) -> Double { -ny * x + nx * y }

  /// Whether (x, y) lies in the masking swath: within ±width of the line, inside the extent.
  package func contains(x: Double, y: Double) -> Bool {
    guard abs(perpendicular(x: x, y: y)) <= Self.dilate * width / 2 else { return false }
    let along = project(x: x, y: y)
    return along >= t0 && along <= t1
  }

  /// Where the line exits the `width` × `height` rectangle, in the extent's coordinate
  /// (`borderT`); nil for a line that crosses fewer than two edges.
  func borderExtent(width: Int, height: Int) -> (Double, Double)? {
    let (dx, dy) = direction
    let (px, py) = (nx * rho, ny * rho)
    let epsilon = 1e-6
    var hits: [Double] = []
    func add(_ along: Double, _ x: Double, _ y: Double) {
      if x >= -epsilon && x <= Double(width) + epsilon && y >= -epsilon
        && y <= Double(height) + epsilon
      {
        hits.append(along)
      }
    }
    if abs(dx) > 1e-9 {
      for edge in [0, Double(width)] {
        let along = (edge - px) / dx
        add(along, edge, py + along * dy)
      }
    }
    if abs(dy) > 1e-9 {
      for edge in [0, Double(height)] {
        let along = (edge - py) / dy
        add(along, px + along * dx, edge)
      }
    }
    guard hits.count >= 2, let low = hits.min(), let high = hits.max() else { return nil }
    return (low, high)
  }

  /// An image-clamped pixel box, bounds inclusive.
  struct Box {
    var xs: ClosedRange<Int>
    var ys: ClosedRange<Int>
  }

  /// The image-clamped bounding box of the swath (`swathBBox`).
  func boundingBox(width: Int, height: Int) -> Box {
    let (dx, dy) = direction
    let (px, py) = (nx * rho, ny * rho)
    let half = Self.dilate * self.width / 2
    var (minX, minY, maxX, maxY) = (
      Double.infinity, Double.infinity, -Double.infinity, -Double.infinity
    )
    for end in [t0, t1] {
      let (bx, by) = (px + end * dx, py + end * dy)
      for side in [-1.0, 1.0] {
        let (cx, cy) = (bx + side * half * nx, by + side * half * ny)
        (minX, maxX) = (min(minX, cx), max(maxX, cx))
        (minY, maxY) = (min(minY, cy), max(maxY, cy))
      }
    }
    return Box(
      xs: Self.clamp(minX.rounded(.down), width)...Self.clamp(maxX.rounded(.up), width),
      ys: Self.clamp(minY.rounded(.down), height)...Self.clamp(maxY.rounded(.up), height))
  }

  /// `int(v)` clamped to [0, size − 1], an infinite or huge bound saturating.
  private static func clamp(_ value: Double, _ size: Int) -> Int {
    guard value.isFinite else { return value > 0 ? size - 1 : 0 }
    return min(max(Int(max(min(value, 1e15), -1e15)), 0), size - 1)
  }
}
