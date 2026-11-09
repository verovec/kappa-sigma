internal import ImageKit
internal import Metal

/// What the next step of a chain preview reads (card 0158), held on the GPU (card 0188).
///
/// As a history at that step would give it: its input image, the context layers and their
/// statistics, whether each written layer was only moved since the stack, and the roles written
/// so far. Nothing is read back between two steps: the image and the layers stay textures, and
/// their statistics are measured there (`GPUStats`).
struct ChainState {
  /// The image the next step receives.
  var image: GPUImage
  /// Its metadata (the plate solution moved by every geometric step so far).
  var metadata: ImageMetadata
  /// Its statistics when already known (the bundle's for the original image), else measured.
  var stats: LayerStats?
  /// The layers the next step reads: the bundle's, overlaid by what the steps wrote.
  var layers: [String: GPUImage]
  /// Their statistics, by id.
  var layerStats: [String: LayerStats]
  /// Whether every step that wrote each id only moved it (`History.note`).
  var onlyMoved: [String: Bool]
  /// The roles the steps so far wrote layers for (`History.layerRoles`).
  var roles: Set<LayerRole>

  /// After `step` of `processID`: what the step after it reads, by the rule of
  /// `History.context` (`moving`: the geometric processes; `stack`: the bundle's layer
  /// statistics, whose continuum fit a moved layer keeps), the written layers measured on the GPU.
  mutating func advance(
    past step: GPUStep, of processID: String, moving: Set<String>,
    stack: [String: LayerStats], measure: GPUStats
  ) throws {
    // A step's role output wins over a bundle layer of the same id, as in `writtenFiles`.
    let written = step.replacing.merging(step.outputs.map { ($0.key.rawValue, $0.value) }) { $1 }
    History.note(written: written.keys, by: processID, moving: moving, in: &onlyMoved)
    for (id, layer) in written {
      layers[id] = layer
      layerStats[id] = History.stats(
        measured: try measure.measure(layer), onlyMoved: onlyMoved[id] == true, stack: stack[id])
    }
    roles.formUnion(step.outputs.keys)
    image = step.result
    metadata = step.metadata
    stats = nil
  }
}
