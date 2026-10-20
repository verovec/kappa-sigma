/// Where a process may act (PixInsight masks): a source, a feather and an inversion, applied by
/// the kit (`ProcessRunner`), never by the process.
package struct Mask: Equatable, Sendable {
  /// What the mask measures.
  package var source: MaskSource
  /// Box-feather radius in full-resolution pixels (divided by the preview scale).
  package var featherPx: Double
  /// 1 − mask.
  package var inverted: Bool

  /// A mask from `source`, feathered by `featherPx`, possibly inverted.
  package init(source: MaskSource, featherPx: Double = 0, inverted: Bool = false) {
    self.source = source
    self.featherPx = featherPx
    self.inverted = inverted
  }
}

/// What a mask is computed from (the image the process runs on).
package enum MaskSource: Equatable, Sendable {
  /// Rec. 709 luma in [low, high], with linear ramps of width `softness` outside.
  case luminosityRange(low: Double, high: Double, softness: Double)
  /// Stars proxy until a star layer exists (0055): luma above its local mean (box of
  /// `radiusPx`) — 0 below `threshold`, ramping to 1 at twice it.
  case stars(threshold: Double, radiusPx: Double)
}
