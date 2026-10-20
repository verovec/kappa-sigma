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
