internal import Foundation
package import ImageKit
package import Metal

/// Runs one process on a history's head the way the Studio and a pipeline both do (cards 0087,
/// 0090): the layers it reads are the bundle's, overlaid by what the applied steps wrote; an
/// applied `GeometricProcess` moves every one of those layers and the header with the image.
package struct StepRunner {
  /// The GPU it runs on.
  package let device: MTLDevice
  /// The stack's layers and statistics.
  package let bundle: PipelineBundle
  private let runner: ProcessRunner
  private let bundleLayers: [String: GPUImage]
  private let cache = ContextCache()

  /// A runner over `bundle` on `device`; the bundle's layers are uploaded once.
  package init(device: MTLDevice, bundle: PipelineBundle) throws {
    self.device = device
    self.bundle = bundle
    runner = try ProcessRunner(device: device)
    bundleLayers = try bundle.layers.mapValues { try GPUImage(device: device, image: $0) }
  }

  /// The statistics the next step of `history` gets: the bundle's for the original image, else
  /// those of the image it receives (shown, never used to change a setting, R2).
  package func stepStats(_ history: History) -> LayerStats {
    history.steps.isEmpty ? bundle.stats : LayerStats.measured(history.current)
  }

  /// The statistics of the layers the next step of `history` reads, by id.
  ///
  /// A layer a step wrote is measured again; a moved bundle layer keeps its recorded continuum
  /// fit (`continuum_k` is the stack's, a crop does not refit it).
  package func layerStats(_ history: History) throws -> [String: LayerStats] {
    try context(history).stats
  }

  /// `process` of `input` (the head by default) at `scale` for `purpose`, under `mask`.
  ///
  /// The preview and Apply both come from here. A geometric process's output carries the input's
  /// plate solution moved with it (none after a fine angle).
  package func render(
    _ process: any ImageProcess, on history: History, input: AstroImage? = nil,
    scale: Double = 1, purpose: RenderContext.Purpose = .apply, mask: AstroImage? = nil
  ) throws -> AstroImage {
    let source = input ?? history.current
    let (layers, layerStats) = try context(history)
    let output = try runner.run(
      process, input: GPUImage(device: device, image: source), stats: stepStats(history),
      scale: scale, purpose: purpose, layers: layers, layerStats: layerStats,
      mask: try mask.map { try GPUImage(device: device, image: $0) },
      rowsBottomUp: source.metadata.rowOrder == .bottomUp)
    var metadata = source.metadata
    if let geometric = process as? any GeometricProcess,
      !type(of: geometric).isIdentity(geometric.params)
    {
      metadata.wcs = try movedWCS(geometric, of: source)
    }
    return AstroImage(
      width: output.width, height: output.height, planes: output.read(), metadata: metadata)
  }

  /// Applies `process` (`processID` with `params`) to the head of `history` under `mask`.
  ///
  /// A geometric step also moves every layer the next steps read: a layer an earlier step wrote
  /// becomes this step's output of that role, a bundle layer one of its `bundleLayers`, all
  /// carrying the moved plate solution.
  package func apply(
    _ process: any ImageProcess, processID: String, params: ParamSet, to history: History,
    mask: AstroImage? = nil
  ) throws {
    let input = history.current
    let result = try render(process, on: history, mask: mask)
    guard let geometric = process as? any GeometricProcess,
      !type(of: geometric).isIdentity(geometric.params)
    else {
      try history.apply(processID: processID, params: params, result: result)
      return
    }
    let roles = history.layerRoles
    var outputs: [LayerRole: AstroImage] = [:]
    var rewritten: [String: AstroImage] = [:]
    for (id, layer) in try context(history).layers {
      guard layer.width == input.width, layer.height == input.height else {
        throw ProcessError.sizeMismatch
      }
      let moved = try runner.run(
        geometric, input: layer, stats: LayerStats(channels: []),
        rowsBottomUp: input.metadata.rowOrder == .bottomUp)
      let image = AstroImage(
        width: moved.width, height: moved.height, planes: moved.read(), metadata: result.metadata)
      if let role = LayerRole(rawValue: id), roles.contains(role) {
        outputs[role] = image
      } else {
        rewritten[id] = image
      }
    }
    try history.apply(
      processID: processID, params: params, result: result, outputs: outputs,
      bundleLayers: rewritten)
  }

  /// The layers a render reads, uploaded, with their statistics: the bundle's, overlaid by the
  /// bundle layers the steps rewrote, then by the layers they wrote by role.
  package func context(_ history: History) throws -> (
    layers: [String: GPUImage], stats: [String: LayerStats]
  ) {
    // Read, uploaded and measured once per state of the history: a preview frame reuses them.
    let key = ContextCache.Key(directory: history.directory, files: history.overlayFiles)
    if let cached = cache.entry, cached.key == key { return (cached.layers, cached.stats) }
    var layers = bundleLayers
    var stats = bundle.layerStats
    for (id, image) in try overlays(history) {
      layers[id] = try GPUImage(device: device, image: image)
      stats[id] = measured(id, image)
    }
    cache.entry = (key, layers, stats)
    return (layers, stats)
  }

  /// What the applied steps wrote over the bundle, by layer id (role outputs last, so a later
  /// tool's starless wins over a bundle layer of that name).
  private func overlays(_ history: History) throws -> [String: AstroImage] {
    var images = try history.bundleLayers()
    for (role, image) in try history.layers() { images[role.rawValue] = image }
    return images
  }

  private func measured(_ id: String, _ image: AstroImage) -> LayerStats {
    let stats = LayerStats.measured(image)
    guard let recorded = bundle.layerStats[id] else { return stats }
    return LayerStats(
      channels: stats.channels, continuumK: recorded.continuumK,
      continuumReference: recorded.continuumReference)
  }

  /// The plate solution of `image` after `process`: its cards moved, or none after an angle.
  private func movedWCS(_ process: any GeometricProcess, of image: AstroImage) throws -> WCS? {
    guard let wcs = image.metadata.wcs else { return nil }
    let moved = try process.header(
      FITSHeader(cards: wcs.cards), width: image.width, height: image.height,
      bottomUp: image.metadata.rowOrder == .bottomUp)
    return WCS(header: moved)
  }
}
