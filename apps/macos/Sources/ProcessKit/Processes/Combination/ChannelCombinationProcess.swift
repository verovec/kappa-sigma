internal import FilterKit
package import Metal

/// Builds the Studio's working RGB image from the bundle layers.
///
/// Design §2, PixInsight's ChannelCombination / LRGBCombination: each slot = weight · max(layer − black, 0), L replaces
/// the luminance at its opacity. The first node of every pipeline; its input only sets the size.
///
/// R2: a source missing from the bundle is an error with the reason, never replaced by another
/// layer (the slot's row says it first, `unavailableReasons(_:layerIDs:)`).
package struct ChannelCombinationProcess: ImageProcess {
  package static let id = "channel-combination"
  package static let title = "Channel combination"
  package static let stage = ProcessStage.linear
  package static let previewExactOnlyAt1to1 = false

  package static let schema: ParamSchema = {
    // No "palette" parameter: a palette only fills the sources (`Palette.apply(to:)`), and the
    // panel names the one the sources match (`Palette.matching`).
    var specs: [ParamSpec] = []
    for (slot, name, source) in [
      ("r", "Red", "RGB.r"), ("g", "Green", "RGB.g"), ("b", "Blue", "RGB.b"),
    ] {
      specs += [
        // A colour slot takes any plane the bundle holds, or √(A·B) of two lines (card 0138).
        ParamSpec(
          id: slot + "Source", title: name, level: .simple, layer: source, allowsNone: false,
          allowsProduct: true),
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
        id: "lSource", title: "Luminance", level: .simple, layer: "none", allowsNone: true,
        allowsProduct: false),
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

  /// The source parameter of each slot, R, G, B, then L.
  package static let slotSources = ["rSource", "gSource", "bSource", "lSource"]

  /// The combination a bundle opens on (card 0138): the palette its layers spell.
  ///
  /// Natural on the colour layer, lrgb / rgb on R, G, B (with L when present), sho on the three
  /// lines, hoo on Hα + OIII — else a grey of its first layer. A colour bundle gets exactly the
  /// schema's defaults: step 0 of an OSC stack keeps its bytes.
  package static func initialParams(layerIDs: Set<String>, planes: [String: Int]) -> ParamSet {
    var params = ParamSet(schema: schema)
    let ids = Set(layerIDs.compactMap(Filter.init(rawValue:)))
    let sources: [String]
    if layerIDs.contains(Filter.color) {
      return params
    } else if ids.isSuperset(of: [.red, .green, .blue]) {
      sources = ids.contains(.luminance) ? Palette.lrgb.sources : ["R", "G", "B", "none"]
    } else if ids.isSuperset(of: [.sulfurII, .hydrogenAlpha, .oxygenIII]) {
      sources = Palette.sho.sources
    } else if ids.isSuperset(of: [.hydrogenAlpha, .oxygenIII]) {
      sources = Palette.hoo.sources
    } else if let first = layerIDs.sorted(by: Filter.less).first {
      let grey =
        planes[first] == 3 ? ["r", "g", "b"].map { "\(first).\($0)" } : [first, first, first]
      sources = grey + ["none"]
    } else {
      return params
    }
    for (slot, source) in zip(slotSources, sources) {
      // Every source above is a layer token by construction: `set` cannot refuse it.
      try? params.set(slot, .choice(source))
    }
    return params
  }

  /// The layers `params` read, in slot order (R, G, B, L).
  package static func layersNeeded(params: ParamSet) -> [String] {
    var needed: [String] = []
    for slot in slotSources {
      for layer in layers(of: params.choice(slot)) where !needed.contains(layer) {
        needed.append(layer)
      }
    }
    return needed
  }

  /// The layers its slots read.
  package static func layersRead(_ params: ParamSet, layerIDs: Set<String>) -> Set<String> {
    Set(layersNeeded(params: params)).intersection(layerIDs)
  }

  /// The sources of the slots that add something: a colour slot at weight 0, an L slot at weight
  /// or opacity 0, puts none of its layer in the image.
  package static func layersMerged(_ params: ParamSet, layerIDs: Set<String>) -> Set<String> {
    var merged = Set<String>()
    for slot in ["r", "g", "b"] where params.number(slot + "Weight") != 0 {
      merged.formUnion(layers(of: params.choice(slot + "Source")))
    }
    if params.number("lWeight") != 0, params.number("lOpacity") != 0 {
      merged.formUnion(layers(of: params.choice("lSource")))
    }
    return merged.intersection(layerIDs)
  }

  /// Its input only sets the size.
  package static let replacesInput = true

  /// The reason a slot's row carries while it reads a layer the stack lacks (card 0135).
  package static let missingLayerReason = "the slot needs a layer the stack lacks"
  package static let rowReasons = [missingLayerReason]

  /// The layers the slots name, whatever the bundle holds.
  package static func layersAsked(_ params: ParamSet) -> Set<String> {
    Set(layersNeeded(params: params))
  }

  /// Each slot whose source names a layer outside `layerIDs`, every missing layer named as the
  /// panel writes it.
  package static func unavailableReasons(_ params: ParamSet, layerIDs: Set<String>)
    -> [String: RowNote]
  {
    var notes: [String: RowNote] = [:]
    for slot in slotSources {
      let missing = layers(of: params.choice(slot)).filter { !layerIDs.contains($0) }
      guard !missing.isEmpty else { continue }
      let names = missing.map(EmissionLine.name(ofLayer:))
      notes[slot] = RowNote(reason: missingLayerReason, subject: names.joined(separator: " + "))
    }
    return notes
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
    let slots = try Self.slotSources.prefix(3).map {
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
      try LayerPlane(id == "RGB" ? source : id).texture(
        in: context.layers, width: size.width, height: size.height)
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
