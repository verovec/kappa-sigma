internal import ImageKit
package import Metal

extension History {
  /// The layers a step reads, and their statistics (cards 0087, 0088).
  ///
  /// The bundle's `layers` and `stats`, overlaid by what the steps applied so far wrote
  /// (`writtenLayers()`: StarNet's starless, a background-extracted Hα…), uploaded to `device`
  /// and measured. The Studio's renders and the pipeline runner read the same. With `before`,
  /// only the steps before that index count: what step `before` read (card 0158).
  ///
  /// A layer only ever written by `moving` steps (geometric processes, card 0090) keeps the
  /// stack's continuum fit: a crop or a turn moves its pixels, not the ratio fitted on them. A
  /// layer any other step rewrote (a background extraction), even if moved since, has none.
  package func context(
    over layers: [String: GPUImage], stats: [String: LayerStats], device: MTLDevice,
    moving: Set<String> = [], before: Int? = nil
  ) throws -> ([String: GPUImage], [String: LayerStats]) {
    let context = try contextAndMoves(
      over: layers, stats: stats, device: device, moving: moving, before: before)
    return (context.layers, context.stats)
  }

  /// `context(over:stats:device:moving:before:)` with the `onlyMoved` map it was built from
  /// (the chain preview carries it on, card 0158).
  func contextAndMoves(
    over layers: [String: GPUImage], stats: [String: LayerStats], device: MTLDevice,
    moving: Set<String>, before: Int?
  ) throws -> (layers: [String: GPUImage], stats: [String: LayerStats], onlyMoved: [String: Bool]) {
    let applied = steps.prefix(before ?? steps.count)
    var layers = layers
    var stats = stats
    let onlyMoved = Self.onlyMoved(applied, moving: moving)
    for (id, file) in Self.writtenFiles(of: applied) {
      let image = try layer(file: file)
      layers[id] = try GPUImage(device: device, image: image)
      stats[id] = Self.stats(ofWritten: image, onlyMoved: onlyMoved[id] == true, stack: stats[id])
    }
    return (layers, stats, onlyMoved)
  }

  /// Whether every one of `steps` that wrote each id only moved it (`note`).
  static func onlyMoved(_ steps: some Sequence<Step>, moving: Set<String>) -> [String: Bool] {
    var onlyMoved: [String: Bool] = [:]
    for step in steps {
      note(written: step.writtenIDs, by: step.processID, moving: moving, in: &onlyMoved)
    }
    return onlyMoved
  }

  /// Records that the step of `processID` wrote `ids` in `onlyMoved`: whether every step that
  /// wrote each id only moved it (`moving` holds the geometric processes), since the stack.
  static func note(
    written ids: some Sequence<String>, by processID: String, moving: Set<String>,
    in onlyMoved: inout [String: Bool]
  ) {
    for id in ids { onlyMoved[id] = (onlyMoved[id] ?? true) && moving.contains(processID) }
  }

  /// The statistics of a layer a step wrote: measured, keeping the `stack` layer's continuum fit
  /// when it was `onlyMoved` since.
  static func stats(ofWritten image: AstroImage, onlyMoved: Bool, stack: LayerStats?)
    -> LayerStats
  {
    let measured = LayerStats.measured(image)
    return onlyMoved ? measured.keepingFit(of: stack) : measured
  }
}

extension History.Step {
  /// The context ids this step wrote: the bundle layers it rewrote and its role outputs.
  var writtenIDs: [String] {
    Array(replaced.keys) + outputs.keys.map(\.rawValue)
  }
}
