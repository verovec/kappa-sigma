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
    Set(boundLines(params).map(\.layerID)).intersection(layerIDs)
  }

  /// The lines the blend kernel reads, in screen order: the enabled ones with α above 0. An
  /// invisible line left the base untouched in the unrolled kernel, so leaving it out changes no
  /// bit (card 0136).
  package static func boundLines(_ params: ParamSet) -> [EmissionLine] {
    enabledLines(params).filter { alpha($0, params: params) > 0 }
  }

  /// The opacity of `line` times the narrowband blend.
  static func alpha(_ line: EmissionLine, params: ParamSet) -> Double {
    params.number(line.id("Opacity")) * params.number("nbBlend")
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
    var lines: [MTLTexture] = []
    var values: [LineKernels.ScreenLine] = []
    for line in Self.boundLines(params) {
      // An invisible line is not prepared: its screen would add exactly nothing.
      guard let stretch = stretches[line] else { continue }
      lines.append(try prepared(line, stretch: stretch, size: input, context: context))
      let rgb = ScreenTint(rawValue: params.choice(line.id("Tint")))?.rgb ?? [0, 0, 0]
      let tint = rgb.map { Float($0) }
      values.append(
        LineKernels.ScreenLine(
          alpha: Float(Self.alpha(line, params: params)), tint: (tint[0], tint[1], tint[2])))
    }
    try encodeBlend(input, into: output, lines: lines, values: values, context: context)
  }

  /// Encodes the blend: base at textures 0–2, each bound line's prepared layer from 3, the free
  /// slots padded with the base, output after them; one `ScreenLine` per bound line at buffer 0
  /// and their count at buffer 1 (see Screens.metal).
  private func encodeBlend(
    _ input: GPUImage, into output: GPUImage, lines: [MTLTexture],
    values: [LineKernels.ScreenLine], context: RenderContext
  ) throws {
    guard values.count <= LineKernels.maxLines else {
      throw ProcessError.invalidParameter("more than \(LineKernels.maxLines) lines")
    }
    guard let encoder = context.commands.makeComputeCommandEncoder() else {
      throw ProcessError.commandFailed("screens encoder")
    }
    let count = UInt32(values.count)
    // setBytes needs bytes even when no line is visible (count 0: the kernel copies the base).
    var values = values.isEmpty ? [LineKernels.ScreenLine(alpha: 0, tint: (0, 0, 0))] : values
    encoder.setComputePipelineState(blend)
    for (index, plane) in input.planes.enumerated() { encoder.setTexture(plane, index: index) }
    for slot in 0..<LineKernels.maxLines {
      encoder.setTexture(slot < lines.count ? lines[slot] : input.planes[0], index: 3 + slot)
    }
    for (index, plane) in output.planes.enumerated() {
      encoder.setTexture(plane, index: 3 + LineKernels.maxLines + index)
    }
    unsafe encoder.setBytes(
      &values, length: values.count * MemoryLayout<LineKernels.ScreenLine>.stride, index: 0)
    var countBytes = count
    unsafe encoder.setBytes(&countBytes, length: MemoryLayout<UInt32>.stride, index: 1)
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
