package import Metal

extension History {
  /// The layers a step reads, and their statistics (cards 0087, 0088).
  ///
  /// The bundle's `layers` and `stats`, overlaid by what the steps applied so far wrote
  /// (`writtenLayers()`: StarNet's starless, a background-extracted Hα…), uploaded to `device`
  /// and measured. The Studio's renders and the pipeline runner read the same.
  ///
  /// A layer only ever written by `moving` steps (geometric processes, card 0090) keeps the
  /// stack's continuum fit: a crop or a turn moves its pixels, not the ratio fitted on them. A
  /// layer any other step rewrote (a background extraction), even if moved since, has none.
  package func context(
    over layers: [String: GPUImage], stats: [String: LayerStats], device: MTLDevice,
    moving: Set<String> = []
  ) throws -> ([String: GPUImage], [String: LayerStats]) {
    var layers = layers
    var stats = stats
    // Whether every step that wrote each id only moved it, since the stack.
    var onlyMoved: [String: Bool] = [:]
    for step in steps {
      let ids = Array(step.replaced.keys) + step.outputs.keys.map(\.rawValue)
      for id in ids { onlyMoved[id] = (onlyMoved[id] ?? true) && moving.contains(step.processID) }
    }
    for (id, file) in writtenFiles {
      let image = try layer(file: file)
      layers[id] = try GPUImage(device: device, image: image)
      let measured = LayerStats.measured(image)
      stats[id] = onlyMoved[id] == true ? measured.keepingFit(of: stats[id]) : measured
    }
    return (layers, stats)
  }
}
