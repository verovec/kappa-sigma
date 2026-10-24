package import ImageKit

/// One bundle layer's own history (card 0118).
///
/// The per-layer linear steps (denoise, colour balance…) made on `RGB`, `Ha` or `OIII` before the
/// layers are combined. Its head replaces the layer for the main history; it never moves pixels
/// (one canvas).
package struct Branch {
  /// The bundle layer it edits.
  package let layerID: String
  /// Its steps, on the layer as stacked.
  package let history: History

  /// The branch of `layerID` over `history`.
  package init(layerID: String, history: History) {
    self.layerID = layerID
    self.history = history
  }

  /// Its head, or `nil` while no step is applied (the layer as stacked).
  package var head: AstroImage? {
    history.steps.isEmpty ? nil : history.current
  }

  /// The file of its head, or `nil` while no step is applied: what a main step records it read.
  package var headFile: String? { history.steps.last?.file }
}
