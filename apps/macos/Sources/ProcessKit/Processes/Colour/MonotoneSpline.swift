/// A monotone cubic Hermite spline through sorted control points (Fritsch–Carlson).
///
/// Monotone control points give a monotone curve with no overshoot (a local extremum gets a flat
/// tangent), which a natural cubic spline does not guarantee; outside the points it is flat.
package struct MonotoneSpline: Sendable {
  private let xs: [Double]
  private let ys: [Double]
  private let slopes: [Double]

  /// The spline through `points` (sorted by x, distinct x, at least 2: a validated `points` value).
  package init(_ points: [CurvePoint]) {
    xs = points.map(\.x)
    ys = points.map(\.y)
    slopes = Self.tangents(xs: xs, ys: ys)
  }

  /// The curve at `x`.
  package func callAsFunction(_ x: Double) -> Double {
    guard let first = xs.first, let last = xs.last, xs.count > 1 else { return ys.first ?? x }
    if x <= first { return ys[0] }
    if x >= last { return ys[ys.count - 1] }
    var segment = 0
    while segment < xs.count - 2, x >= xs[segment + 1] { segment += 1 }
    let width: Double = xs[segment + 1] - xs[segment]
    let along: Double = (x - xs[segment]) / width
    let t2: Double = along * along
    let t3: Double = t2 * along
    let start: Double = (2 * t3 - 3 * t2 + 1) * ys[segment]
    let startTangent: Double = (t3 - 2 * t2 + along) * width * slopes[segment]
    let end: Double = (3 * t2 - 2 * t3) * ys[segment + 1]
    let endTangent: Double = (t3 - t2) * width * slopes[segment + 1]
    return start + startTangent + end + endTangent
  }

  /// The curve sampled at i / (size − 1), the table the shader interpolates.
  package func lut(size: Int = CurvesProcess.lutSize) -> [Float] {
    (0..<size).map { Float(self(Double($0) / Double(size - 1))) }
  }

  /// Fritsch–Carlson tangents: the secants' harmonic-style mean, zero at an extremum, limited so
  /// α² + β² ≤ 9 on every segment.
  private static func tangents(xs: [Double], ys: [Double]) -> [Double] {
    let count = xs.count
    guard count > 1 else { return [0] }
    var secants: [Double] = []
    for index in 0..<count - 1 {
      let rise: Double = ys[index + 1] - ys[index]
      let run: Double = xs[index + 1] - xs[index]
      secants.append(rise / run)
    }
    var slopes = [Double](repeating: 0, count: count)
    slopes[0] = secants[0]
    slopes[count - 1] = secants[count - 2]
    for index in 1..<max(1, count - 1) {
      let left: Double = secants[index - 1]
      let right: Double = secants[index]
      slopes[index] = left * right <= 0 ? 0 : (left + right) / 2
    }
    for index in 0..<count - 1 {
      let secant: Double = secants[index]
      guard secant != 0 else {
        slopes[index] = 0
        slopes[index + 1] = 0
        continue
      }
      let alpha: Double = slopes[index] / secant
      let beta: Double = slopes[index + 1] / secant
      let norm: Double = alpha * alpha + beta * beta
      if norm > 9 {
        let tau: Double = 3 / norm.squareRoot()
        slopes[index] = tau * alpha * secant
        slopes[index + 1] = tau * beta * secant
      }
    }
    return slopes
  }
}
