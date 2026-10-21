internal import Foundation

/// The MTF stretch of one emission layer, astrocomp's `mtfParams`, computed on the CPU from the
/// bundle statistics (R2: the shader never measures the layer).
///
/// Shadows c = median + clip · MADN (≥ 0); the midtone sends the normalised median
/// x₀ = (median − c) / (1 − c) to the target background. This is NOT the Siril form of
/// `StretchProcess` (midtone from median − c, not normalised): astrocomp is the oracle here.
package struct LineStretch: Equatable, Sendable {
  /// The linear background median the stretch was computed from.
  package let median: Double
  /// The linear background noise (MADN) it was computed from.
  package let madn: Double
  /// c.
  package let shadows: Double
  /// m.
  package let midtone: Double

  /// The stretch sending `median` to `target`, shadows `clip` MADN from it.
  ///
  /// Refused, with the reason, when the shadows reach the median: the curve would be a hard
  /// threshold, never rendered as such nor adjusted silently (R2).
  package init(median: Double, madn: Double, clip: Double, target: Double, name: String) throws {
    let shadows = max(median + clip * madn, 0)
    guard shadows < 1, median > shadows else {
      throw ProcessError.invalidParameter(
        "\(name): the shadows clip reaches the background median (\(median), MADN \(madn))")
    }
    let x0 = (median - shadows) / (1 - shadows)
    self.median = median
    self.madn = madn
    self.shadows = shadows
    midtone = x0 * (1 - target) / (x0 - 2 * target * x0 + target)
  }

  private init(median: Double, madn: Double, shadows: Double, midtone: Double) {
    self.median = median
    self.madn = madn
    self.shadows = shadows
    self.midtone = midtone
  }

  /// This curve applied to another layer's background (`linkLayers`): the same shadows and
  /// midtone, that layer's own median and MADN for its noise.
  package func linked(median: Double, madn: Double) -> Self {
    Self(median: median, madn: madn, shadows: shadows, midtone: midtone)
  }

  /// The background noise after the stretch: the MADN times the curve's slope at the median.
  ///
  /// The unit of the black point's σ label and suggestion: the black point is applied to the
  /// stretched layer, so its σ is the stretched noise, derived from the bundle MADN. 0 for a
  /// (linked) background at or below the shadows, which the curve sends to black.
  package var stretchedNoise: Double {
    let x0 = (median - shadows) / (1 - shadows)
    guard x0 > 0 else { return 0 }
    let denominator = (2 * midtone - 1) * x0 - midtone
    return midtone * (1 - midtone) / (denominator * denominator) / (1 - shadows) * madn
  }
}
