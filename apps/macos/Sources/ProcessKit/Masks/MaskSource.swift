/// What a mask is computed from (the image the process runs on).
package enum MaskSource: Equatable, Sendable {
  /// Rec. 709 luma in [low, high], with linear ramps of width `softness` outside.
  case luminosityRange(low: Double, high: Double, softness: Double)
  /// Stars proxy until a star layer exists (0055): luma above its local mean (box of
  /// `radiusPx`), 0 below `threshold`, ramping to 1 at twice it.
  case stars(threshold: Double, radiusPx: Double)

  /// Why this source cannot be computed (it would give NaN or an empty range), or `nil`.
  package var problem: String? {
    switch self {
    case .luminosityRange(let low, let high, let softness):
      guard [low, high, softness].allSatisfy(\.isFinite) else {
        return "range values must be finite"
      }
      if low > high { return "range low \(low) above high \(high)" }
      if softness < 0 { return "softness \(softness) below 0" }
    case .stars(let threshold, let radiusPx):
      guard threshold.isFinite, threshold > 0 else { return "stars threshold must be above 0" }
      guard radiusPx.isFinite, radiusPx > 0 else { return "stars radius must be above 0" }
    }
    return nil
  }
}
