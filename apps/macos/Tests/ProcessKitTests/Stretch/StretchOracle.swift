import Foundation

/// The stretch references, in double, written from their sources and not from the kernel.
///
/// - MTF: astrocomp `mtf`, with Siril's autostretch parameters (`find_unlinked_midtones_balance`
///   and `find_linked_midtones_balance`: the midtone from median − c0, not normalised by 1 − c0).
/// - GHS: the equations of the Generalised Hyperbolic Stretch paper (Cranfield & Payne), as
///   Siril's `ght` implements them.
/// - Headroom: the legacy `nightscape.CompressHighlights` shoulder.
enum StretchOracle {
  static func mtf(_ x: Double, _ m: Double) -> Double {
    if x <= 0 { return 0 }
    if x >= 1 { return 1 }
    return (m - 1) * x / ((2 * m - 1) * x - m)
  }

  /// (c0, m) of one channel, or of the averaged channels when linked.
  static func autostretch(median: Double, madn: Double, clip: Double, target: Double) -> (
    shadows: Double, midtone: Double
  ) {
    let shadows = min(max(median + clip * madn, 0), 1)
    return (shadows, mtf(median - shadows, target))
  }

  static func stretchMTF(_ x: Double, shadows: Double, midtone: Double) -> Double {
    mtf((x - shadows) / (1 - shadows), midtone)
  }

  // MARK: GHS

  /// The base transform T and its derivative for intensity `b`, strength `d`.
  static func base(_ x: Double, b: Double, d: Double) -> (value: Double, slope: Double) {
    if b == -1 { return (log(1 + d * x), d / (1 + d * x)) }
    if b < 0 {
      return (
        (1 - pow(1 - b * d * x, (b + 1) / b)) / (d * (b + 1)), pow(1 - b * d * x, 1 / b)
      )
    }
    if b == 0 { return (1 - exp(-d * x), d * exp(-d * x)) }
    return (1 - pow(1 + b * d * x, -1 / b), d * pow(1 + b * d * x, -(1 + b) / b))
  }

  /// The piecewise curve before normalisation.
  static func ghsRaw(_ x: Double, d: Double, b: Double, lp: Double, sp: Double, hp: Double)
    -> Double
  {
    if x < lp {
      let edge = base(sp - lp, b: b, d: d)
      return -edge.value + edge.slope * (x - lp)
    }
    if x < sp { return -base(sp - x, b: b, d: d).value }
    if x < hp { return base(x - sp, b: b, d: d).value }
    let edge = base(hp - sp, b: b, d: d)
    return edge.value + edge.slope * (x - hp)
  }

  /// GHS of `x` with ln(D + 1) = `stretch`; the identity when D = 0.
  static func ghs(_ x: Double, stretch: Double, b: Double, lp: Double, sp: Double, hp: Double)
    -> Double
  {
    let d = exp(stretch) - 1
    let clamped = min(max(x, 0), 1)
    guard d > 0 else { return clamped }
    let low = ghsRaw(0, d: d, b: b, lp: lp, sp: sp, hp: hp)
    let high = ghsRaw(1, d: d, b: b, lp: lp, sp: sp, hp: hp)
    return (ghsRaw(clamped, d: d, b: b, lp: lp, sp: sp, hp: hp) - low) / (high - low)
  }

  // MARK: Headroom and asinh

  static func luminance(_ pixel: [Double]) -> Double {
    pixel.count == 3 ? 0.299 * pixel[0] + 0.587 * pixel[1] + 0.114 * pixel[2] : pixel[0]
  }

  /// `CompressHighlights(knee = ceiling − 0.05, ceiling)`: identity at 1 (off).
  static func headroom(_ pixel: [Double], ceiling: Double) -> [Double] {
    guard ceiling > 0, ceiling < 1 else { return pixel }
    let knee = ceiling - 0.05 > 0 ? ceiling - 0.05 : ceiling * 0.9
    let lum = luminance(pixel)
    guard lum > knee else { return pixel }
    let compressed = knee + (ceiling - knee) * tanh((lum - knee) / (ceiling - knee))
    return pixel.map { $0 * compressed / lum }
  }

  /// Ratio-preserving asinh above the black point; a channel over 1 scales the pixel down.
  static func asinhStretch(_ pixel: [Double], beta: Double, black: Double) -> [Double] {
    let lifted = pixel.map { max(($0 - black) / (1 - black), 0) }
    guard beta > 0 else { return lifted.map { min($0, 1) } }
    let lum = luminance(lifted)
    guard lum > 0 else { return lifted.map { _ in 0 } }
    let scaled = lifted.map { $0 * asinh(beta * lum) / (asinh(beta) * lum) }
    let peak = scaled.max() ?? 0
    return peak > 1 ? scaled.map { $0 / peak } : scaled
  }
}
