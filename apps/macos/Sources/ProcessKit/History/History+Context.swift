package import Metal

extension History {
  /// The layers a step reads, and their statistics (cards 0087, 0088).
  ///
  /// The bundle's `layers` and `stats`, overlaid by what the steps applied so far wrote
  /// (`writtenLayers()`: StarNet's starless, a background-extracted Hα…), uploaded to `device`
  /// and measured. The Studio's renders and the pipeline runner read the same.
  package func context(
    over layers: [String: GPUImage], stats: [String: LayerStats], device: MTLDevice
  ) throws -> ([String: GPUImage], [String: LayerStats]) {
    var layers = layers
    var stats = stats
    for (id, image) in try writtenLayers() {
      layers[id] = try GPUImage(device: device, image: image)
      // Measured again (a crop changes the sample), keeping the stack's continuum fit.
      stats[id] = LayerStats.measured(image).keepingFit(of: stats[id])
    }
    return (layers, stats)
  }
}
