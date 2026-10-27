package import Metal

/// Adds the emission lines into the linear broadband base (E22, « booster mon Hα / OIII face à
/// du BB »): per line and target plane `p`, `base_p + gain · share_p · max(line − k·ref − black, 0)`.
///
/// Linear, unlike the emission screens: the line is not stretched here, so a later stretch reads
/// base and line together. No normalisation and no clip: values above 1 stay (the stretch has
/// headroom). R2: the bundle's `continuum_k` is a suggestion shown with its reference plane, never
/// a default; every gain defaults to 0, which returns the head bit for bit. The formula has no
/// legacy rule (legacy « hargb » was a screen); PixInsight's NBRGBCombination is the idea, the CPU
/// oracle in the tests pins it.
package struct LineInjectionProcess: ImageProcess {
  package static let id = "line-injection"
  package static let title = "Line injection"
  package static let stage = ProcessStage.linear
  package static let requires: [LayerRole] = [.color, .emission]
  package static let previewExactOnlyAt1to1 = false

  /// The planes a line can go into, in base order (the suffixes of the share ids).
  static let shareSuffixes = ["Red", "Green", "Blue"]

  package let params: ParamSet
  private let pipeline: MTLComputePipelineState

  package init(params: ParamSet, device: MTLDevice) throws {
    self.params = params
    pipeline = try ProcessLibrary.pipeline(
      device: device, file: "LineInjection.metal", function: "lineInjection")
  }

  /// What `line` adds to each base plane per unit of excess with `params`: gain × share, as the
  /// kernel reads it (a Double too small for a Float adds nothing).
  package static func weights(_ line: EmissionLine, params: ParamSet) -> [Float] {
    let gain = params.number(line.id("Gain"))
    return shareSuffixes.map { Float(gain * params.number(line.id($0))) }
  }

  /// Whether `line` adds something with `params`: the one rule for reading its layer.
  package static func injects(_ line: EmissionLine, params: ParamSet) -> Bool {
    weights(line, params: params).contains { $0 != 0 }
  }

  /// The line layers that inject, and every broadband layer once one of them subtracts its
  /// continuum (the plane k multiplies is the bundle's fit, unknown from the values alone).
  package static func layersRead(_ params: ParamSet, layerIDs: Set<String>) -> Set<String> {
    let continuum = EmissionLine.allCases.contains {
      injects($0, params: params) && subtracts($0, params: params)
    }
    return layersMerged(params, layerIDs: layerIDs)
      .union(continuum ? layerIDs.subtracting(EmissionLine.layerIDs) : [])
  }

  /// The lines that inject: the broadband a continuum subtracts is not added.
  package static func layersMerged(_ params: ParamSet, layerIDs: Set<String>) -> Set<String> {
    Set(EmissionLine.allCases.filter { injects($0, params: params) }.map(\.layerID))
      .intersection(layerIDs)
  }

  /// The reason an injecting line's rows carry while its layer is absent (card 0135).
  package static let lineLayerReason = "the injection needs its line layer"
  package static let rowReasons = [lineLayerReason]

  /// The lines whose gain is set: what the panel keeps on screen even without the layer.
  ///
  /// The gain is the line's switch (the shares are its colour): shares dragged to 0 inject
  /// nothing, yet the rows stay so the gain can be reset and the shares restored.
  package static func layersAsked(_ params: ParamSet) -> Set<String> {
    Set(
      EmissionLine.allCases.filter { Float(params.number($0.id("Gain"))) != 0 }.map(\.layerID))
  }

  /// Whether `line` subtracts its continuum with `params`: k as the kernel reads it (Float).
  package static func subtracts(_ line: EmissionLine, params: ParamSet) -> Bool {
    Float(params.number(line.id("ContinuumK"))) != 0
  }

  package func render(
    _ input: GPUImage, stats: LayerStats, into output: GPUImage, context: RenderContext
  ) throws {
    guard output.planes.count == input.planes.count, output.width == input.width,
      output.height == input.height
    else { throw ProcessError.sizeMismatch }
    // Nothing to add changes no bit (not even −0.0): the head goes through as it is.
    guard EmissionLine.allCases.contains(where: { Self.injects($0, params: params) }) else {
      return try ColourKernel.copy(input, into: output, commands: context.commands)
    }
    guard input.planes.count == 3 else {
      throw ProcessError.invalidParameter("line injection needs an RGB base")
    }
    var textures: [MTLTexture] = []
    var values: [Float] = []
    for line in EmissionLine.allCases {
      // A line that adds nothing needs no layer: the kernel skips zero weights.
      let (plane, reference) =
        Self.injects(line, params: params)
        ? try planes(line, size: input, context: context) : (input.planes[0], input.planes[0])
      textures += [plane, reference]
      values +=
        Self.weights(line, params: params)
        + [params.number(line.id("ContinuumK")), params.number(line.id("Black"))]
        .map(Float.init)
    }
    try encode(input, into: output, lines: textures, values: values, context: context)
  }

  /// The plane of `line` and the plane k multiplies (the line itself when k = 0: no reference
  /// needed then).
  private func planes(
    _ line: EmissionLine, size: GPUImage, context: RenderContext
  ) throws -> (MTLTexture, MTLTexture) {
    let plane = try LayerPlane(line.layerID).texture(
      in: context.layers, width: size.width, height: size.height)
    guard Self.subtracts(line, params: params) else { return (plane, plane) }
    guard let token = context.layerStats[line.layerID]?.continuumReference else {
      throw ProcessError.invalidParameter(
        "\(line.name): the bundle has no continuum fit: set k to 0")
    }
    let reference = try LayerPlane(token).texture(
      in: context.layers, width: size.width, height: size.height)
    return (plane, reference)
  }

  /// Encodes the kernel: base at textures 0–2, output at 3–5, then each line's plane and
  /// reference from 6; five values per line at buffer 0 (see LineInjection.metal).
  private func encode(
    _ input: GPUImage, into output: GPUImage, lines: [MTLTexture], values: [Float],
    context: RenderContext
  ) throws {
    guard let encoder = context.commands.makeComputeCommandEncoder() else {
      throw ProcessError.commandFailed("line injection encoder")
    }
    var values = values
    encoder.setComputePipelineState(pipeline)
    for (index, plane) in input.planes.enumerated() { encoder.setTexture(plane, index: index) }
    for (index, plane) in output.planes.enumerated() { encoder.setTexture(plane, index: 3 + index) }
    for (index, texture) in lines.enumerated() { encoder.setTexture(texture, index: 6 + index) }
    unsafe encoder.setBytes(&values, length: values.count * MemoryLayout<Float>.stride, index: 0)
    encoder.dispatchThreads(
      MTLSize(width: output.width, height: output.height, depth: 1),
      threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
    encoder.endEncoding()
  }
}
