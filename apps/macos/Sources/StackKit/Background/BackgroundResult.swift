package import ImageKit

/// What an extraction returns: the corrected image and the model that was taken out of the input
/// (`input − corrected` for a subtraction, `input ÷ corrected` for a division), same size and
/// row order as the input.
package struct BackgroundResult {
  /// The image without its background.
  package let corrected: AstroImage
  /// The background the engine modelled, as the user may view it.
  package let model: AstroImage
  /// Whether the pair came from the cache (no tool ran).
  package let reused: Bool

  /// A result from its parts.
  package init(corrected: AstroImage, model: AstroImage, reused: Bool) {
    self.corrected = corrected
    self.model = model
    self.reused = reused
  }
}
