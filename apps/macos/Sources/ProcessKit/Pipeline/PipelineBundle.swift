package import ImageKit

/// What a pipeline runs against (card 0059).
///
/// The bundle's statistics of the image, and its layers with their statistics for the processes
/// that read them (combination, screens, stars). Given, never measured by the runner (R2).
package struct PipelineBundle {
  /// The statistics of the image the pipeline starts from.
  package var stats: LayerStats
  /// The bundle's layers by id (`RGB`, `Ha`, `OIII`, `starless`…), at the image's size.
  package var layers: [String: AstroImage]
  /// Their statistics by id.
  package var layerStats: [String: LayerStats]

  /// A bundle of `stats`, `layers` and `layerStats`.
  package init(
    stats: LayerStats, layers: [String: AstroImage] = [:], layerStats: [String: LayerStats] = [:]
  ) {
    self.stats = stats
    self.layers = layers
    self.layerStats = layerStats
  }
}
