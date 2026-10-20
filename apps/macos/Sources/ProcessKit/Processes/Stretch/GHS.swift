internal import Foundation

/// The Generalised Hyperbolic Stretch equations (Cranfield & Payne, as Siril's `ght`), in double.
///
/// The base transform T of local intensity `b` and strength D is logarithmic (b = −1), integral
/// (b < 0), exponential (b = 0) or hyperbolic (b > 0); the curve mirrors T below the symmetry
/// point and continues it linearly below the shadow and above the highlight protection points.
enum GHS {
  /// T(x) and T′(x).
  static func base(_ x: Double, b: Double, d: Double) -> (value: Double, slope: Double) {
    if b == -1 { return (log(1 + d * x), d / (1 + d * x)) }
    if b < 0 {
      return ((1 - pow(1 - b * d * x, (b + 1) / b)) / (d * (b + 1)), pow(1 - b * d * x, 1 / b))
    }
    if b == 0 { return (1 - exp(-d * x), d * exp(-d * x)) }
    return (1 - pow(1 + b * d * x, -1 / b), d * pow(1 + b * d * x, -(1 + b) / b))
  }

  /// The piecewise curve at `x`, before normalisation.
  static func raw(
    _ x: Double, b: Double, d: Double, lp: Double, sp: Double, hp: Double
  ) -> Double {
    if x < lp {
      let edge = base(sp - lp, b: b, d: d)
      return -edge.value + edge.slope * (x - lp)
    }
    if x < sp { return -base(sp - x, b: b, d: d).value }
    if x < hp { return base(x - sp, b: b, d: d).value }
    let edge = base(hp - sp, b: b, d: d)
    return edge.value + edge.slope * (x - hp)
  }
}
