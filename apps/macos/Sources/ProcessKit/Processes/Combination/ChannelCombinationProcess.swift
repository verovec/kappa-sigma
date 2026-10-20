package import Metal

/// Builds the Studio's working RGB image from the bundle layers.
///
/// Design §2, PixInsight's ChannelCombination / LRGBCombination: each slot = weight · max(layer − black, 0), L replaces
/// the luminance at its opacity. The first node of every pipeline; its input only sets the size.
///
/// R2: a source missing from the bundle is an error with the reason, never replaced by another
/// layer (`unavailableReason` greys the option first).
package struct ChannelCombinationProcess: ImageProcess {
  package static let id = "channel-combination"
  package static let title = "Channel combination"
  package static let stage = ProcessStage.linear
  package static let previewExactOnlyAt1to1 = false

  /// Layer planes a colour slot can take; `A*B` is √(A·B).
  package static let colorSources = [
    "RGB.r", "RGB.g", "RGB.b", "R", "G", "B", "L", "Ha", "OIII", "SII", "Ha*OIII",
  ]
  /// What the L slot can take.
  package static let luminanceSources = ["none", "L", "Ha", "R", "G", "B"]

  package static let schema: ParamSchema = {
    // No "palette" parameter: a palette only fills the sources (`Palette.apply(to:)`), and the
    // panel names the one the sources match (`Palette.matching`).
    var specs: [ParamSpec] = []
    for (slot, name, source) in [
      ("r", "Red", "RGB.r"), ("g", "Green", "RGB.g"), ("b", "Blue", "RGB.b"),
    ] {
      specs += [
        ParamSpec(
          id: slot + "Source", title: name, level: .simple, choice: source, of: colorSources),
        ParamSpec(
          id: slot + "Weight", title: name + " weight", unit: .none, level: .advanced, number: 1,
          in: 0...4),
        ParamSpec(
          id: slot + "Black", title: name + " black", unit: .none, level: .advanced, number: 0,
          in: 0...1),
      ]
    }
    specs += [
      ParamSpec(
        id: "lSource", title: "Luminance", level: .simple, choice: "none", of: luminanceSources),
      ParamSpec(
        id: "lWeight", title: "L weight", unit: .none, level: .advanced, number: 1, in: 0...4),
      ParamSpec(
        id: "lBlack", title: "L black", unit: .none, level: .advanced, number: 0, in: 0...1),
      ParamSpec(
        id: "lOpacity", title: "L opacity", unit: .opacity, level: .simple, number: 1, in: 0...1),
    ]
    return ParamSchema(specs)
  }()

  /// Always RGB, whatever the working image it replaces.
  package static func outputChannels(input: Int) -> Int { 3 }

  package let params: ParamSet
  private let pipeline: MTLComputePipelineState

  package init(params: ParamSet, device: MTLDevice) throws {
    self.params = params
    pipeline = try ProcessLibrary.pipeline(
      device: device, file: "Combination.metal", function: "combineChannels")
  }

  /// The layers `params` read, in slot order (R, G, B, L).
  package static func layersNeeded(params: ParamSet) -> [String] {
    var needed: [String] = []
    for slot in ["rSource", "gSource", "bSource", "lSource"] {
      for layer in layers(of: params.choice(slot)) where !needed.contains(layer) {
        needed.append(layer)
      }
    }
    return needed
  }

  /// Why `params` cannot run with only `present` layers ("HOO needs the OIII layer"), or `nil`.
  package static func unavailableReason(params: ParamSet, present: Set<String>) -> String? {
    guard let missing = layersNeeded(params: params).first(where: { !present.contains($0) }) else {
      return nil
    }
    let name = Palette.matching(params)?.title ?? "This combination"
    return "\(name) needs the \(missing) layer"
  }

  package func render(
    _ input: GPUImage, stats: LayerStats, into output: GPUImage, context: RenderContext
  ) throws {
    guard output.planes.count == 3 else { throw ProcessError.sizeMismatch }
    let size = (width: output.width, height: output.height)
    let slots = try ["rSource", "gSource", "bSource"].map {
      try planes(params.choice($0), context, size: size)
    }
    let luminance = try planes(params.choice("lSource"), context, size: size)
    guard let encoder = context.commands.makeComputeCommandEncoder() else {
      throw ProcessError.commandFailed("combination encoder")
    }
    encoder.setComputePipelineState(pipeline)
    for (index, slot) in slots.enumerated() {
      encoder.setTexture(slot.first, index: index)
      encoder.setTexture(slot.second ?? slot.first, index: 3 + index)
    }
    encoder.setTexture(luminance.first ?? slots[0].first, index: 6)
    for (index, plane) in output.planes.enumerated() { encoder.setTexture(plane, index: 7 + index) }
    var values = uniforms(slots: slots, hasLuminance: luminance.first != nil)
    unsafe encoder.setBytes(&values, length: values.count * MemoryLayout<Float>.stride, index: 0)
    encoder.dispatchThreads(
      MTLSize(width: output.width, height: output.height, depth: 1),
      threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
    encoder.endEncoding()
  }

  /// The kernel's `p[]` (see Combination.metal).
  private func uniforms(slots: [SlotPlanes], hasLuminance: Bool) -> [Float] {
    let weights = ["r", "g", "b"].map { Float(params.number($0 + "Weight")) }
    let blacks = ["r", "g", "b"].map { Float(params.number($0 + "Black")) }
    let means: [Float] = slots.map { $0.second == nil ? 0 : 1 }
    return weights + blacks + means + [
      Float(params.number("lWeight")), Float(params.number("lBlack")),
      Float(params.number("lOpacity")), hasLuminance ? 1 : 0,
    ]
  }

  /// One slot's textures: a plane, and the second plane of a `A*B` source.
  private struct SlotPlanes {
    let first: MTLTexture?
    let second: MTLTexture?
  }

  private func planes(
    _ source: String, _ context: RenderContext, size: (width: Int, height: Int)
  ) throws -> SlotPlanes {
    let textures = try Self.layers(of: source).map { id -> MTLTexture in
      guard let layer = context.layers[id] else { throw ProcessError.missingLayer(id) }
      // A layer of another size would be read at the wrong pixels: never silently.
      guard layer.width == size.width, layer.height == size.height else {
        throw ProcessError.sizeMismatch
      }
      let plane = ["RGB.r": 0, "RGB.g": 1, "RGB.b": 2][source] ?? 0
      guard plane < layer.planes.count else { throw ProcessError.missingLayer(source) }
      return layer.planes[plane]
    }
    return SlotPlanes(first: textures.first, second: textures.count > 1 ? textures[1] : nil)
  }

  /// The layer ids a source token reads.
  private static func layers(of source: String) -> [String] {
    if source == "none" { return [] }
    if source.hasPrefix("RGB.") { return ["RGB"] }
    return source.split(separator: "*").map(String.init)
  }
}
