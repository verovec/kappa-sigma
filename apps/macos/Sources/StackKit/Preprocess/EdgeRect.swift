/// A half-open pixel rectangle [x0, x1) × [y0, y1) (`edgeRect`).
package struct EdgeRect: Equatable, Sendable, Codable {
  package var x0: Int
  package var y0: Int
  package var x1: Int
  package var y1: Int

  /// The rectangle with these corners.
  package init(x0: Int, y0: Int, x1: Int, y1: Int) {
    self.x0 = x0
    self.y0 = y0
    self.x1 = x1
    self.y1 = y1
  }

  package var width: Int { x1 - x0 }
  package var height: Int { y1 - y0 }
  package var area: Int { width * height }

  /// The part this rectangle shares with `other`.
  package func intersect(_ other: Self) -> Self {
    Self(x0: max(x0, other.x0), y0: max(y0, other.y0), x1: min(x1, other.x1), y1: min(y1, other.y1))
  }
}
