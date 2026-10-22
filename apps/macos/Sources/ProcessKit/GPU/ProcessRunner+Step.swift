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
    let output = try run(
      process, input: GPUImage(device: device, image: input), stats: stats, scale: scale,
      purpose: purpose, layers: layers, layerStats: layerStats,
      mask: try mask.map { try GPUImage(device: device, image: $0) },
      rowsBottomUp: input.metadata.rowOrder == .bottomUp)
    var metadata = input.metadata
    if let geometric = Self.moving(process) {
      metadata.wcs = try Self.movedWCS(geometric, of: input)
    }
    return AstroImage(
      width: output.width, height: output.height, planes: output.read(), metadata: metadata)
  }

  /// The layers an applied `process` step moves with its image (card 0090): every context layer
  /// of a geometric step, as the step's outputs of the roles earlier steps wrote (`roles`) and as
  /// replaced bundle layers otherwise; nothing for any other process or at the identity.
  package func movedLayers(
    _ process: any ImageProcess, layers: [String: GPUImage], input: AstroImage,
    result: AstroImage, roles: Set<LayerRole>
  ) throws -> (outputs: [LayerRole: AstroImage], replacing: [String: AstroImage]) {
    guard let geometric = Self.moving(process) else { return ([:], [:]) }
    var outputs: [LayerRole: AstroImage] = [:]
    var replacing: [String: AstroImage] = [:]
    for (id, layer) in layers {
      guard layer.width == input.width, layer.height == input.height else {
        throw ProcessError.sizeMismatch
      }
      let moved = try run(
        geometric, input: layer, stats: LayerStats(channels: []),
        rowsBottomUp: input.metadata.rowOrder == .bottomUp)
      let image = AstroImage(
        width: moved.width, height: moved.height, planes: moved.read(), metadata: result.metadata)
      if let role = LayerRole(rawValue: id), roles.contains(role) {
        outputs[role] = image
      } else {
        replacing[id] = image
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

  /// The plate solution of `image` after `process`: its cards moved, or none after an angle.
  private static func movedWCS(_ process: any GeometricProcess, of image: AstroImage) throws
    -> WCS?
  {
    guard let wcs = image.metadata.wcs else { return nil }
    let moved = try process.header(
      FITSHeader(cards: wcs.cards), width: image.width, height: image.height,
      bottomUp: image.metadata.rowOrder == .bottomUp)
    return WCS(header: moved)
  }
}
