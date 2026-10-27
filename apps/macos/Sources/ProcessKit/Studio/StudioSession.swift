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
  /// The stack's layers and statistics, each branch head over its layer (card 0118): what the
  /// main history reads.
  package internal(set) var bundle: PipelineBundle
  /// The stack's layers and statistics as stacked: what the branches start from.
  package let stackBundle: PipelineBundle
  /// The per-layer histories (card 0118).
  package let branches: BranchSet
  /// The processes it runs (the catalogue lists the same).
  package let registry: ProcessRegistry
  /// The GPU it runs on (the viewer draws on the same one).
  package let device: MTLDevice
  let runner: ProcessRunner
  /// The layers of `bundle` on the GPU: the stack's, uploaded once, and the branch heads.
  var bundleLayers: [String: GPUImage]
  /// The last manual Apply left the image, its solution and its layers as they were (an
  /// amount at 0, a process switched off, a mask letting nothing through): recorded all the
  /// same — the pipeline keeps its steps — but worth saying, since undoing it shows nothing.
  package internal(set) var lastApplyChangedNothing = false
  var overlay: Overlay?

  /// A session over `history` and `bundle`, running the processes of `registry` on `device`;
  /// `branches` are those beside the history's folder unless given.
  package init(
    history: History, bundle: PipelineBundle, registry: ProcessRegistry, device: MTLDevice,
    branches: BranchSet? = nil
  ) throws {
    self.history = history
    stackBundle = bundle
    self.registry = registry
    self.device = device
    let branches =
      try branches
      ?? BranchSet(
        folder: BranchSet.folder(besides: history.directory), bundle: bundle,
        schema: { registry.type(id: $0)?.schema })
    self.branches = branches
    self.bundle = branches.overlay(bundle, baseID: Self.baseLayerID(bundle.layers.keys))
    runner = try ProcessRunner(device: device)
    bundleLayers = try self.bundle.layers.mapValues { try GPUImage(device: device, image: $0) }
    // A history opened over the stacked base layer starts from its branch head (card 0118).
    if let baseID = Self.baseLayerID(bundle.layers.keys), let head = branches.branch(baseID)?.head {
      history.rebase(onto: head)
    }
    history.branchHeadsRead = { [weak self] processID, params, index in
      self?.headsRead(processID, params: params, index: index) ?? [:]
    }
  }

  /// The statistics of `image` as a layer's (a bundle built from files, a step's output).
  package static func stats(of image: AstroImage) -> LayerStats {
    LayerStats.measured(image)
  }

  /// The ids of the layers the next step can read: the bundle's and the step outputs'.
  package func layerIDs() -> Set<String> {
    Set(bundle.layers.keys).union(history.layerRoles.map(\.rawValue))
  }

  /// The planes of each layer the next step can read (card 0138): the bundle's, and the step
  /// outputs' as the renderer holds them (an output not loadable yet counts as the bundle says).
  package func layerPlanes() -> [String: Int] {
    let bundlePlanes = bundle.layers.mapValues { $0.planes.count }
    guard let loaded = try? context().0 else { return bundlePlanes }
    return bundlePlanes.merging(loaded.mapValues { $0.planes.count }) { $1 }
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
    let (layers, layerStats) = try context()
    return try runner.image(
      type.init(params: params, device: device), input: input ?? history.current,
      stats: stepStats, scale: scale, purpose: purpose, layers: layers, layerStats: layerStats,
      mask: mask)
  }

  /// Applies `processID` with `params` at full resolution: the head moves to its result; a
  /// geometry step moves every layer the next steps read with it (card 0090).
  package func apply(_ processID: String, params: ParamSet, mask: AstroImage? = nil) throws {
    guard let type = registry.type(id: processID) else {
      throw StudioError.unknownProcess(processID)
    }
    if type.runsTool(params) { throw StudioError.needsTool(processID) }
    let process = try type.init(params: params, device: device)
    let input = history.current
    let (layers, layerStats) = try context()
    let result = try runner.image(
      process, input: input, stats: stepStats, layers: layers, layerStats: layerStats, mask: mask)
    let moved = try runner.movedLayers(
      process, layers: layers, input: input, result: result, roles: history.layerRoles)
    lastApplyChangedNothing = false
    let unchanged =
      result.width == input.width && result.height == input.height
      && result.metadata == input.metadata && Self.samePixels(result.planes, input.planes)
    try history.apply(
      processID: processID, params: params, result: result, outputs: moved.outputs,
      replacing: moved.replacing, movesPixels: registry.movesPixels(processID, params: params))
    lastApplyChangedNothing = unchanged && moved.outputs.isEmpty && moved.replacing.isEmpty
  }

  /// Whether `one` and `two` hold the same bits: a NaN equals itself.
  package static func samePixels(_ one: [[Float]], _ two: [[Float]]) -> Bool {
    one.count == two.count
      && zip(one, two).allSatisfy { first, second in
        first.elementsEqual(second) { $0.bitPattern == $1.bitPattern }
      }
  }

  /// The statistics of the layers the next step reads, by id.
  package func layerStats() throws -> [String: LayerStats] {
    try context().1
  }

  /// Records a step whose result was made elsewhere (a host tool), with the layers it wrote and
  /// the bundle layers it rewrote (card 0092).
  package func apply(
    _ processID: String, params: ParamSet, result: AstroImage,
    outputs: [LayerRole: AstroImage] = [:], replacing: [String: AstroImage] = [:]
  ) throws {
    lastApplyChangedNothing = false
    try history.apply(
      processID: processID, params: params, result: result, outputs: outputs,
      replacing: replacing)
  }

  /// Runs the host tool `batch` as the step `id` with `params` on the head, its progress (0…1)
  /// handed to `onProgress`: the layer it writes overlays the bundle for the steps after it.
  package func apply(
    _ batch: PipelineRunner.BatchProcess, id: String, params: ParamSet,
    onProgress: @escaping @Sendable (Double) -> Void
  ) async throws {
    try await batch.record(
      id, params: params, in: history, bundle: bundle, onProgress: onProgress)
  }

  /// The layers a render reads: the bundle's, overlaid by what the applied steps wrote.
  ///
  /// The overlay is read, measured and uploaded once per set of step files (a starless is
  /// ~260 MB at 22 Mpx), not at every preview.
  func context() throws -> ([String: GPUImage], [String: LayerStats]) {
    let files = history.writtenFiles
    if let overlay, overlay.files == files { return (overlay.layers, overlay.stats) }
    let (layers, stats) = try history.context(
      over: bundleLayers, stats: bundle.layerStats, device: device, moving: registry.movingIDs)
    overlay = Overlay(files: files, layers: layers, stats: stats)
    return (layers, stats)
  }

  /// The context of the step files `files`.
  struct Overlay {
    let files: [String: String]
    let layers: [String: GPUImage]
    let stats: [String: LayerStats]
  }
}
