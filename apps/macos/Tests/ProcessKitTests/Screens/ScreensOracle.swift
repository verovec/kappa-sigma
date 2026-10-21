import Foundation

/// The emission screens in double, written from astrocomp's `main.go` (stretchLayer, blackClip,
/// the OIII boost, opening, screen) and not from the kernel.
enum ScreensOracle {
  /// One line's settings, as astrocomp's flags give them.
  struct Line {
    var shadows: Double
    var midtone: Double
    var black = 0.0
    var boost = 1.0
    var k: Double?
  }

  /// astrocomp `mtfParams`: (c, m).
  static func mtfParams(median: Double, madn: Double, target: Double, clip: Double) -> (
    shadows: Double, midtone: Double
  ) {
    let shadows = max(median + clip * madn, 0)
    let x0 = (median - shadows) / (1 - shadows)
    return (shadows, x0 * (1 - target) / (x0 - 2 * target * x0 + target))
  }

  static func mtf(_ x: Double, _ midtone: Double) -> Double {
    if x <= 0 { return 0 }
    if x >= 1 { return 1 }
    return (midtone - 1) * x / ((2 * midtone - 1) * x - midtone)
  }

  /// A line pixel before the opening: continuum, stretch, black clip, boost.
  static func prepare(_ value: Float, reference: Float = 0, _ line: Line) -> Double {
    var linear = Double(value)
    if let k = line.k { linear = max(linear - k * Double(reference), 0) }
    var x = mtf((linear - line.shadows) / (1 - line.shadows), line.midtone)
    if line.black > 0 { x = max((x - line.black) / (1 - line.black), 0) }
    if line.boost > 1 {
      let (knee, span) = (0.60, 0.98 - 0.60)
      x *= line.boost
      if x > knee { x = knee + span * tanh((x - knee) / span) }
    }
    return x
  }

  /// astrocomp's screen with a tint: bv + op·(s − bv), s = 1 − (1 − bv)(1 − lv·t).
  static func screen(base: Double, value: Double, alpha: Double, tint: Double) -> Double {
    guard value > 0 else { return base }
    let screened = 1 - (1 - base) * (1 - value * tint)
    return base + alpha * (screened - base)
  }
}
