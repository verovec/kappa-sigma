package import ImageKit
package import Metal

/// The Studio's processing over one stack (card 0087): its history, the bundle's layers
/// uploaded once, and the layers earlier steps wrote overlaid on them.
///
/// What a step reads is what `PipelineRunner` gives it: the bundle's statistics for the first
/// step, then those of the image the step receives (shown, never used to change a setting, R2).
/// The app wraps it (`StudioModel`) to mirror the history in the project and feed the viewer.
package final class StudioSession {
  /// The non-destructive history; its head is the working image.
  package let history: History
  /// The stack's layers and statistics.
  package let bundle: PipelineBundle
  /// The processes it runs (the catalogue lists the same).
  package let registry: ProcessRegistry
  /// The GPU it runs on (the viewer draws on the same one).
  package let device: MTLDevice
  private let runner: ProcessRunner
  private let bundleLayers: [String: GPUImage]

  /// A session over `history` and `bundle`, running the processes of `registry` on `device`.
  package init(
    history: History, bundle: PipelineBundle, registry: ProcessRegistry, device: MTLDevice
  ) throws {
    self.history = history
    self.bundle = bundle
    self.registry = registry
    self.device = device
    runner = try ProcessRunner(device: device)
    bundleLayers = try bundle.layers.mapValues { try GPUImage(device: device, image: $0) }
  }

  /// The statistics of `image` as a layer's (a bundle built from files, a step's output).
  package static func stats(of image: AstroImage) -> LayerStats {
    LayerStats.measured(image)
  }

  /// The ids of the layers the next step can read: the bundle's and the step outputs'.
  package func layerIDs() -> Set<String> {
    Set(bundle.layers.keys).union(history.layerRoles.map(\.rawValue))
  }

  /// The layer the working image starts from: `RGB`, else the first id in order (never the
  /// dictionary's order, which changes from one launch to the next).
  package static func baseLayerID(_ ids: some Collection<String>) -> String? {
    ids.contains("RGB") ? "RGB" : ids.sorted().first
  }

  /// The roles present for the next step (a process's `requires` is checked against them).
  package func presentRoles(base: Set<LayerRole>) -> Set<LayerRole> {
    base.union(history.layerRoles)
  }

  /// The statistics the next step gets.
  package var stepStats: LayerStats {
    history.steps.isEmpty ? bundle.stats : LayerStats.measured(history.current)
  }

  /// `processID` with `params` on `input` (the head by default) at `scale` for `purpose`,
  /// under `mask`: the preview and Apply both come from here.
  package func render(
    _ processID: String, params: ParamSet, input: AstroImage? = nil, scale: Double = 1,
    purpose: RenderContext.Purpose = .apply, mask: AstroImage? = nil
  ) throws -> AstroImage {
    guard let type = registry.type(id: processID) else {
      throw StudioError.unknownProcess(processID)
    }
    let source = input ?? history.current
    let (layers, layerStats) = try context()
    let output = try runner.run(
      type.init(params: params, device: device), input: GPUImage(device: device, image: source),
      stats: stepStats, scale: scale, purpose: purpose, layers: layers, layerStats: layerStats,
      mask: try mask.map { try GPUImage(device: device, image: $0) })
    return AstroImage(
      width: source.width, height: source.height, planes: output.read(),
      metadata: source.metadata)
  }

  /// Applies `processID` with `params` at full resolution: the head moves to its result.
  package func apply(_ processID: String, params: ParamSet, mask: AstroImage? = nil) throws {
    if registry.type(id: processID)?.hostTool == true { throw StudioError.needsTool(processID) }
    let result = try render(processID, params: params, mask: mask)
    try history.apply(processID: processID, params: params, result: result)
  }

  /// Records a step whose result was made elsewhere (a host tool), with the layers it wrote.
  package func apply(
    _ processID: String, params: ParamSet, result: AstroImage,
    outputs: [LayerRole: AstroImage] = [:]
  ) throws {
    try history.apply(processID: processID, params: params, result: result, outputs: outputs)
  }

  /// The layers a render reads: the bundle's, overlaid by the outputs of the applied steps.
  private func context() throws -> ([String: GPUImage], [String: LayerStats]) {
    try history.context(over: bundleLayers, stats: bundle.layerStats, device: device)
  }
}
