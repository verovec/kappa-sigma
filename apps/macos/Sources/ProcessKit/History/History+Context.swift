package import Metal

extension History {
  /// The layers a step reads, and their statistics (cards 0087, 0088).
  ///
  /// The bundle's `layers` and `stats`, overlaid by the outputs of the steps applied so far
  /// (StarNet's starless…), uploaded to `device` and measured. The Studio's renders and the
  /// pipeline runner read the same.
  package func context(
    over layers: [String: GPUImage], stats: [String: LayerStats], device: MTLDevice
  ) throws -> ([String: GPUImage], [String: LayerStats]) {
    var layers = layers
    var stats = stats
    for (role, image) in try self.layers() {
      layers[role.rawValue] = try GPUImage(device: device, image: image)
      stats[role.rawValue] = LayerStats.measured(image)
    }
    return (layers, stats)
  }
}
