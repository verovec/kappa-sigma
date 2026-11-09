package import ImageKit
internal import Metal

// MARK: - One step on a history's head (cards 0087, 0090)

extension ProcessRunner {
  /// `process` of `input` with the context `layers`, as an image the size the process makes:
  /// what the Studio's preview and Apply and the pipeline runner all record.
  ///
  /// A geometric process's output carries `input`'s plate solution moved with it (none after a
  /// fine angle); at its identity values nothing is moved.
  package func image(
    _ process: any ImageProcess, input: AstroImage, stats: LayerStats, scale: Double = 1,
    purpose: RenderContext.Purpose = .apply, layers: [String: GPUImage] = [:],
    layerStats: [String: LayerStats] = [:], mask: AstroImage? = nil
  ) throws -> AstroImage {
    let (output, metadata) = try image(
      process, input: (try GPUImage(device: device, image: input), input.metadata),
      stats: stats, scale: scale, purpose: purpose, layers: layers, layerStats: layerStats,
      mask: try mask.map { try GPUImage(device: device, image: $0) })
    return output.image(metadata: metadata)
  }

  /// `image(_:input:…)` on the GPU (card 0188): `input` is the texture with the metadata it
  /// carries, and the output stays one.
  package func image(
    _ process: any ImageProcess, input: (image: GPUImage, metadata: ImageMetadata),
    stats: LayerStats, scale: Double = 1, purpose: RenderContext.Purpose = .apply,
    layers: [String: GPUImage] = [:], layerStats: [String: LayerStats] = [:],
    mask: GPUImage? = nil
  ) throws -> (image: GPUImage, metadata: ImageMetadata) {
    let bottomUp = input.metadata.rowOrder == .bottomUp
    let output = try run(
      process, input: input.image, stats: stats, scale: scale, purpose: purpose, layers: layers,
      layerStats: layerStats, mask: mask, rowsBottomUp: bottomUp)
    var moved = input.metadata
    if let geometric = Self.moving(process) {
      // The header plan is at full resolution: a reduced render carries no solution rather than
      // one moved by the wrong amount.
      moved.wcs =
        scale == 1
        ? try Self.movedWCS(
          geometric, of: input.metadata, width: input.image.width, height: input.image.height,
          bottomUp: bottomUp)
        : nil
    }
    return (output, moved)
  }

  /// `process` applied to `input` at full resolution: its image and the layers it moves.
  ///
  /// The one step of the Studio's Apply, the pipeline runner and the chain preview (card 0158),
  /// reading the context `layers` (`movedLayers` says what moves).
  package func applied(
    _ process: any ImageProcess, input: AstroImage, stats: LayerStats,
    layers: [String: GPUImage], layerStats: [String: LayerStats], roles: Set<LayerRole>,
    mask: AstroImage? = nil
  ) throws -> (
    result: AstroImage, outputs: [LayerRole: AstroImage], replacing: [String: AstroImage]
  ) {
    let step = try applied(
      process, input: (try GPUImage(device: device, image: input), input.metadata),
      stats: stats, layers: layers, layerStats: layerStats, roles: roles,
      mask: try mask.map { try GPUImage(device: device, image: $0) })
    let read = { (image: GPUImage) in image.image(metadata: step.metadata) }
    return (read(step.result), step.outputs.mapValues(read), step.replacing.mapValues(read))
  }

  /// `applied(_:input:…)` on the GPU (card 0188): the chain preview's step, every image a
  /// texture until the chain's last.
  package func applied(
    _ process: any ImageProcess, input: (image: GPUImage, metadata: ImageMetadata),
    stats: LayerStats, layers: [String: GPUImage], layerStats: [String: LayerStats],
    roles: Set<LayerRole>, mask: GPUImage? = nil
  ) throws -> GPUStep {
    let (result, moved) = try image(
      process, input: input, stats: stats, layers: layers, layerStats: layerStats, mask: mask)
    let layers = try movedLayers(
      process, layers: layers, width: input.image.width, height: input.image.height,
      bottomUp: input.metadata.rowOrder == .bottomUp, roles: roles)
    return GPUStep(
      result: result, metadata: moved, outputs: layers.outputs, replacing: layers.replacing)
  }

  /// The layers an applied `process` step moves with its image (card 0090): every context layer
  /// of a geometric step, as the step's outputs of the roles earlier steps wrote (`roles`) and as
  /// replaced bundle layers otherwise; nothing for any other process or at the identity.
  package func movedLayers(
    _ process: any ImageProcess, layers: [String: GPUImage], width: Int, height: Int,
    bottomUp: Bool, roles: Set<LayerRole>
  ) throws -> (outputs: [LayerRole: GPUImage], replacing: [String: GPUImage]) {
    guard let geometric = Self.moving(process) else { return ([:], [:]) }
    var outputs: [LayerRole: GPUImage] = [:]
    var replacing: [String: GPUImage] = [:]
    for (id, layer) in layers {
      guard layer.width == width, layer.height == height else { throw ProcessError.sizeMismatch }
      let moved = try run(
        geometric, input: layer, stats: LayerStats(channels: []), rowsBottomUp: bottomUp)
      if let role = LayerRole(rawValue: id), roles.contains(role) {
        outputs[role] = moved
      } else {
        replacing[id] = moved
      }
    }
    return (outputs, replacing)
  }

  /// `process` as a geometric process that moves pixels, or `nil`.
  private static func moving(_ process: any ImageProcess) -> (any GeometricProcess)? {
    guard let geometric = process as? any GeometricProcess,
      !type(of: geometric).isIdentity(geometric.params)
    else { return nil }
    return geometric
  }

  /// The plate solution of an image of `metadata` after `process`: its cards moved, or none
  /// after an angle.
  private static func movedWCS(
    _ process: any GeometricProcess, of metadata: ImageMetadata, width: Int, height: Int,
    bottomUp: Bool
  ) throws -> WCS? {
    guard let wcs = metadata.wcs else { return nil }
    let moved = try process.header(
      FITSHeader(cards: wcs.cards), width: width, height: height, bottomUp: bottomUp)
    return WCS(header: moved)
  }
}
