/// The control points a `CurveEditor` edits.
///
/// Both coordinates in [0, 1], sorted by x, distinct, between 2 and `maxCount` points; the two
/// ends keep their x. A point the user adds keeps
/// `minimumGap` from the others; loaded points are kept as the process applies them (R2).
///
/// RenderKit never imports ProcessKit: the app converts these to the process's `points`
/// parameter, which validates them again.
package struct CurveEditorPoints: Equatable, Sendable {
  /// The points, sorted by x.
  package private(set) var points: [SIMD2<Double>]
  /// The most points the curve may hold.
  package let maxCount: Int
  /// The smallest x distance between two points.
  package static let minimumGap = 0.01
  private static let identity = [SIMD2<Double>(0, 0), SIMD2(1, 1)]

  /// An editor over `points` (the identity by default) — a validated `points` parameter, kept as
  /// is: clamped, sorted, one point per x; anything else falls back to the identity.
  package init(points: [SIMD2<Double>]? = nil, maxCount: Int) {
    self.maxCount = max(2, maxCount)
    let sorted = (points ?? Self.identity).map(Self.clamped).sorted { $0.x < $1.x }
    let distinct = zip(sorted, sorted.dropFirst()).allSatisfy { $0.x < $1.x }
    self.points =
      (2...self.maxCount).contains(sorted.count) && distinct ? sorted : Self.identity
  }

  /// The straight line from (0, 0) to (1, 1): the curve changes nothing.
  package var isIdentity: Bool { points == Self.identity }

  /// Inserts `point` in x order between the two ends, unless the curve is full or a point is within
  /// `minimumGap` (a point beyond an end would silently become the new end).
  package mutating func add(_ point: SIMD2<Double>) {
    let point = Self.clamped(point)
    guard points.count < maxCount, let first = points.first, let last = points.last,
      point.x > first.x, point.x < last.x,
      points.allSatisfy({ abs($0.x - point.x) >= Self.minimumGap })
    else { return }
    let index = points.firstIndex { $0.x > point.x } ?? points.count
    points.insert(point, at: index)
  }

  /// Moves point `index` toward `target`: clamped into [0, 1], kept `minimumGap` from its
  /// neighbours; the two ends keep their x.
  package mutating func move(_ index: Int, to target: SIMD2<Double>) {
    guard points.indices.contains(index) else { return }
    var point = Self.clamped(target)
    if index == 0 || index == points.count - 1 {
      point.x = points[index].x
    } else {
      let low = points[index - 1].x + Self.minimumGap
      let high = points[index + 1].x - Self.minimumGap
      // Neighbours closer than two gaps leave no room: the point keeps its x.
      point.x = low <= high ? min(max(point.x, low), high) : points[index].x
    }
    points[index] = point
  }

  /// Removes point `index`, unless it is an end or the curve would fall below two points.
  package mutating func remove(_ index: Int) {
    guard index > 0, index < points.count - 1 else { return }
    points.remove(at: index)
  }

  /// Back to the identity.
  package mutating func reset() {
    points = Self.identity
  }

  /// The point nearest `location`, if it lies within `reach` (both in curve units).
  package func nearest(to location: SIMD2<Double>, within reach: Double) -> Int? {
    let distances = points.map { ($0 - location).squaredLength }
    guard let best = distances.indices.min(by: { distances[$0] < distances[$1] }),
      distances[best] <= reach * reach
    else { return nil }
    return best
  }

  private static func clamped(_ point: SIMD2<Double>) -> SIMD2<Double> {
    SIMD2(min(max(point.x, 0), 1), min(max(point.y, 0), 1))
  }
}

extension SIMD2 where Scalar == Double {
  fileprivate var squaredLength: Double { x * x + y * y }
}
