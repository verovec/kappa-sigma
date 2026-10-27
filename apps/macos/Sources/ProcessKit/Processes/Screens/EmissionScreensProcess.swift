package import Metal

/// Screens the emission layers over the stretched colour base (R4, "intensifier certaines
/// couches"): astrocomp's HOO-over-broadband chain, every step a visible parameter.
///
/// Per enabled line, on its own linear bundle layer: optional continuum subtraction
/// (line − k·reference, clamped at 0, k and the reference plane from the bundle fit), the
/// astrocomp MTF stretch (`LineStretch`, from the bundle statistics), a black point, the OIII-style
/// tanh boost (knee 0.60, ceiling 0.98), a grey opening that removes point stars, an optional
/// 3-box smoothing; then `out_c = base_c + α · line · tint_c · (1 − base_c)` in line order, with
/// α = opacity · narrowband blend.
///
/// R2: no wash gate, no automatic attenuation (the legacy `hagate.go` was rejected): k, the black
/// point (shown in σ) and the opacities are values the user sees and may take as suggestions.
package struct EmissionScreensProcess: ImageProcess {
  package static let id = "emission-screens"
  package static let title = "Emission screens"
  package static let stage = ProcessStage.nonlinear
  package static let requires: [LayerRole] = [.color, .emission]
  package static let previewExactOnlyAt1to1 = true

  /// Always RGB: the screens colour the base.
  package static func outputChannels(input: Int) -> Int { 3 }

  package let params: ParamSet
  private let prepare: MTLComputePipelineState
  private let blend: MTLComputePipelineState
  private let morphology: GreyMorphology
  private let blur: BoxBlur

  package init(params: ParamSet, device: MTLDevice) throws {
    self.params = params
    let library = try ProcessLibrary.library(device: device, file: "Screens.metal")
    prepare = try ProcessLibrary.pipeline(library: library, function: "screenLinePrepare")
    blend = try ProcessLibrary.pipeline(library: library, function: "screenBlend")
    morphology = try GreyMorphology(device: device)
    blur = try BoxBlur(device: device)
  }

  /// The enabled lines, in screen order.
  package var enabledLines: [EmissionLine] { Self.enabledLines(params) }

  /// The lines `params` enable, in screen order.
  package static func enabledLines(_ params: ParamSet) -> [EmissionLine] {
    EmissionLine.allCases.filter { params.flag($0.id("Enabled")) }
  }

  /// The enabled lines' layers; with a continuum subtraction, the broadband layers too (the
  /// plane the stack fitted the continuum against is one of them).
  package static func layersRead(_ params: ParamSet, layerIDs: Set<String>) -> Set<String> {
    let enabled = enabledLines(params)
    let continuum = enabled.contains { params.flag($0.id("Continuum")) }
    return Set(enabled.map(\.layerID))
      .union(continuum ? layerIDs.subtracting(EmissionLine.layerIDs) : [])
      .intersection(layerIDs)
  }

  /// The enabled lines `render` lays in (opacity and blend above 0): the broadband a continuum
  /// subtracts is not laid in.
  package static func layersMerged(_ params: ParamSet, layerIDs: Set<String>) -> Set<String> {
    let visible = enabledLines(params).filter {
      params.number($0.id("Opacity")) * params.number("nbBlend") > 0
    }
    return Set(visible.map(\.layerID)).intersection(layerIDs)
  }

  /// The reason an enabled line's rows carry while its layer is absent (card 0135).
  package static let lineLayerReason = "the screen needs its line layer"
  package static let unavailableReasons = [lineLayerReason]

  /// The lines the values enable: what the panel keeps on screen even without the layer.
  package static func layersAsked(_ params: ParamSet) -> Set<String> {
    Set(enabledLines(params).map(\.layerID))
  }

  /// Each enabled line without its layer, on its on/off row, named as the panel writes it.
  package static func unavailableReasons(_ params: ParamSet, layerIDs: Set<String>)
    -> [String: RowNote]
  {
    let missing = enabledLines(params).filter { !layerIDs.contains($0.layerID) }
    return Dictionary(
      uniqueKeysWithValues: missing.map {
        ($0.id("Enabled"), RowNote(reason: lineLayerReason, subject: $0.name))
      })
  }

  /// Why `params` cannot run with only the `present` layers ("Hα screen needs the Ha layer").
  package static func unavailableReason(params: ParamSet, present: Set<String>) -> String? {
    let missing = EmissionLine.allCases.first {
      params.flag($0.id("Enabled")) && !present.contains($0.layerID)
    }
    return missing.map { "\($0.name) screen needs the \($0.layerID) layer" }
  }

  package func render(
    _ input: GPUImage, stats: LayerStats, into output: GPUImage, context: RenderContext
  ) throws {
    guard input.planes.count == 3, output.planes.count == 3, output.width == input.width,
      output.height == input.height
    else { throw ProcessError.sizeMismatch }
    let stretches = try lineStretches(layerStats: context.layerStats)
    var lines: [MTLTexture?] = []
    var values: [Float] = []
    for line in EmissionLine.allCases {
      let alpha = params.number(line.id("Opacity")) * params.number("nbBlend")
      // An invisible line is not prepared: its screen would add exactly nothing.
      guard let stretch = stretches[line], alpha > 0 else {
        lines.append(nil)
        values += [0, 0, 0, 0]
        continue
      }
      lines.append(try prepared(line, stretch: stretch, size: input, context: context))
      let tint = ScreenTint(rawValue: params.choice(line.id("Tint")))?.rgb ?? [0, 0, 0]
      values += ([alpha] + tint).map(Float.init)
    }
    guard let encoder = context.commands.makeComputeCommandEncoder() else {
      throw ProcessError.commandFailed("screens encoder")
    }
    encoder.setComputePipelineState(blend)
    for (index, plane) in input.planes.enumerated() { encoder.setTexture(plane, index: index) }
    for (index, line) in lines.enumerated() {
      encoder.setTexture(line ?? input.planes[0], index: 3 + index)
    }
    for (index, plane) in output.planes.enumerated() { encoder.setTexture(plane, index: 6 + index) }
    unsafe encoder.setBytes(&values, length: values.count * MemoryLayout<Float>.stride, index: 0)
    encoder.dispatchThreads(
      MTLSize(width: output.width, height: output.height, depth: 1),
      threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
    encoder.endEncoding()
  }

  /// The layer of `line`, ready to screen.
  ///
  /// Continuum, stretch, black point, boost, then the opening and smoothing at the working scale.
  private func prepared(
    _ line: EmissionLine, stretch: LineStretch, size: GPUImage, context: RenderContext
  ) throws -> MTLTexture {
    let device = context.commands.device
    let plane = try LayerPlane(line.layerID).texture(
      in: context.layers, width: size.width, height: size.height)
    let subtract = params.flag(line.id("Continuum"))
    let reference =
      subtract
      ? try LayerPlane(continuumReference(line, layerStats: context.layerStats)).texture(
        in: context.layers, width: size.width, height: size.height) : plane
    var result = try ScratchTexture.make(like: plane, device: device)
    guard let encoder = context.commands.makeComputeCommandEncoder() else {
      throw ProcessError.commandFailed("screen layer encoder")
    }
    var values = prepareUniforms(line, stretch: stretch).map(Float.init)
    encoder.setComputePipelineState(prepare)
    encoder.setTexture(plane, index: 0)
    encoder.setTexture(reference, index: 1)
    encoder.setTexture(result, index: 2)
    unsafe encoder.setBytes(&values, length: values.count * MemoryLayout<Float>.stride, index: 0)
    encoder.dispatchThreads(
      MTLSize(width: size.width, height: size.height, depth: 1),
      threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
    encoder.endEncoding()
    let radius = MaskBuilder.workingRadius(params.number("starRadius"), scale: context.scale)
    if radius > 0 {
      let opened = try ScratchTexture.make(like: plane, device: device)
      try morphology.encodeOpening(result, into: opened, radius: radius, commands: context.commands)
      result = opened
    }
    let smooth = MaskBuilder.workingRadius(params.number("smooth"), scale: context.scale)
    if smooth > 0 {
      let blurred = try ScratchTexture.make(like: plane, device: device)
      try blur.encode(
        result, into: blurred, radii: [smooth, smooth, smooth], commands: context.commands)
      result = blurred
    }
    return result
  }

  /// The kernel's `p[]` (see Screens.metal).
  private func prepareUniforms(_ line: EmissionLine, stretch: LineStretch) -> [Double] {
    [
      params.flag(line.id("Continuum")) ? 1 : 0, params.number(line.id("ContinuumK")),
      stretch.shadows, stretch.midtone, params.number(line.id("Black")),
      params.number(line.id("Boost")),
    ]
  }
}
