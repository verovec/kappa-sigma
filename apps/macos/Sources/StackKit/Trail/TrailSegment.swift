internal import Foundation

/// One detected trail (`trail.Segment`): the line n·p = c in full-resolution pixels (n = (nx, ny)
/// a unit normal), masked over t ∈ [t0, t1] along the direction (−ny, nx), with a Gaussian full
/// width `width` (px, FWHM). `score` is the Hough span confidence.
package struct TrailSegment: Equatable, Sendable {
  package var nx: Double
  package var ny: Double
  package var c: Double
  package var t0: Double
  package var t1: Double
  package var width: Double
  package var score: Double

  /// The swath covers ±`dilate`·width/2 = ±width of the line.
  static let dilate = 2.0

  /// A segment.
  package init(
    nx: Double, ny: Double, c: Double, t0: Double = 0, t1: Double = 0, width: Double = 2,
    score: Double = 0
  ) {
    self.nx = nx
    self.ny = ny
    self.c = c
    self.t0 = t0
    self.t1 = t1
    self.width = width
    self.score = score
  }

  /// The unit direction along the line.
  package var direction: (Double, Double) { (-ny, nx) }

  /// The signed perpendicular distance of (x, y) from the line.
  func perpendicular(x: Double, y: Double) -> Double { nx * x + ny * y - c }

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
    let (px, py) = (nx * c, ny * c)
    let epsilon = 1e-6
    var hits: [Double] = []
    func add(_ t: Double, _ x: Double, _ y: Double) {
      if x >= -epsilon && x <= Double(width) + epsilon && y >= -epsilon
        && y <= Double(height) + epsilon
      {
        hits.append(t)
      }
    }
    if abs(dx) > 1e-9 {
      for edge in [0, Double(width)] {
        let t = (edge - px) / dx
        add(t, edge, py + t * dy)
      }
    }
    if abs(dy) > 1e-9 {
      for edge in [0, Double(height)] {
        let t = (edge - py) / dy
        add(t, px + t * dx, edge)
      }
    }
    guard hits.count >= 2, let low = hits.min(), let high = hits.max() else { return nil }
    return (low, high)
  }

  /// The image-clamped bounding box of the swath (`swathBBox`): x0, y0, x1, y1 inclusive.
  func boundingBox(width: Int, height: Int) -> (x0: Int, y0: Int, x1: Int, y1: Int) {
    let (dx, dy) = direction
    let (px, py) = (nx * c, ny * c)
    let half = Self.dilate * self.width / 2
    var (minX, minY, maxX, maxY) = (Double.infinity, Double.infinity, -Double.infinity, -Double.infinity)
    for t in [t0, t1] {
      let (bx, by) = (px + t * dx, py + t * dy)
      for side in [-1.0, 1.0] {
        let (cx, cy) = (bx + side * half * nx, by + side * half * ny)
        (minX, maxX) = (min(minX, cx), max(maxX, cx))
        (minY, maxY) = (min(minY, cy), max(maxY, cy))
      }
    }
    return (
      Self.clamp(minX.rounded(.down), width), Self.clamp(minY.rounded(.down), height),
      Self.clamp(maxX.rounded(.up), width), Self.clamp(maxY.rounded(.up), height)
    )
  }

  /// `int(v)` clamped to [0, size − 1], an infinite or huge bound saturating.
  private static func clamp(_ value: Double, _ size: Int) -> Int {
    guard value.isFinite else { return value > 0 ? size - 1 : 0 }
    return min(max(Int(max(min(value, 1e15), -1e15)), 0), size - 1)
  }
}
