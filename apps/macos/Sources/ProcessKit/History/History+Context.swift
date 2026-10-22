package import Metal

extension History {
  /// The layers a step reads, and their statistics (cards 0087, 0088).
  ///
  /// The bundle's `layers` and `stats`, overlaid by what the steps applied so far wrote
  /// (`writtenLayers()`: StarNet's starless, a background-extracted Hα…), uploaded to `device`
  /// and measured. The Studio's renders and the pipeline runner read the same.
  ///
  /// A layer last written by one of `moving` (geometric processes, card 0090) keeps the stack's
  /// continuum fit: a crop or a turn moves its pixels, not the ratio fitted on them. A layer any
  /// other step rewrote (a background extraction) has no fit until one is made on it.
  package func context(
    over layers: [String: GPUImage], stats: [String: LayerStats], device: MTLDevice,
    moving: Set<String> = []
  ) throws -> ([String: GPUImage], [String: LayerStats]) {
    var layers = layers
    var stats = stats
    var writers: [String: String] = [:]
    for step in steps {
      for file in step.outputs.values { writers[file] = step.processID }
      for file in step.replaced.values { writers[file] = step.processID }
    }
    for (id, file) in writtenFiles {
      let image = try layer(file: file)
      layers[id] = try GPUImage(device: device, image: image)
      let measured = LayerStats.measured(image)
      stats[id] =
        moving.contains(writers[file] ?? "") ? measured.keepingFit(of: stats[id]) : measured
    }
    return (layers, stats)
  }
}
