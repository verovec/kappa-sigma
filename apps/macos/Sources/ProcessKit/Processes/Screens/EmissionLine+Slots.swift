internal import FilterKit

/// The « Other line » slots (card 0164, PO 02/11 option A): static cards whose layer parameter
/// names a bundle line layer kept as written (`Filter5`, `NII-custom`). Static ids keep recipes,
/// history, pipelines and profiles loadable without the bundle; a slot naming `none` reads nothing.
extension EmissionLine {
  /// The slots each line process offers: the kernels take 8 lines, the catalogue fills 5.
  package static let slots = 1...4

  /// The prefix of a slot's parameter ids (`custom1Gain`…).
  package static func slotPrefix(_ slot: Int) -> String { "custom\(slot)" }

  /// How panels write slot `slot`.
  package static func slotName(_ slot: Int) -> String { "Other line \(slot)" }

  /// The id of a slot's layer parameter.
  package static func slotLayerID(_ slot: Int) -> String { slotPrefix(slot) + "Layer" }

  /// The layer parameter of slot `slot`: `none` by default, whole layers only (no product).
  static func slotLayerSpec(_ slot: Int) -> ParamSpec {
    let id = slotLayerID(slot)
    return ParamSpec(
      id: id, title: slotName(slot) + " layer", level: .simple, layer: "none", allowsNone: true,
      allowsProduct: false
    ).about(layerIn: id)
  }

  /// Every line `params` can read: the catalogue, then each slot bound to a layer, in slot order.
  package static func lines(_ params: ParamSet) -> [Self] {
    allCases
      + slots.compactMap { slot in
        let layer = params.choice(slotLayerID(slot))
        return layer.isEmpty || layer == "none" ? nil : custom(slot: slot, layer: layer)
      }
  }

  /// The bundle's line layers outside the catalogue, in the canonical filter order: what a slot
  /// lists.
  package static func customLayers(in layerIDs: some Sequence<String>) -> [String] {
    layerIDs.filter { isLineLayer($0) && !Self.layerIDs.contains($0) }.sorted(by: Filter.less)
  }

  /// The slot pickers to hide: those naming `none` past the bundle's count of custom layers (one
  /// « Other line » card per custom layer); a slot naming a layer always shows (R2: never hidden
  /// from the user who set it).
  package static func hiddenSlotPickers(_ params: ParamSet, layerIDs: Set<String>) -> Set<String> {
    let offered = customLayers(in: layerIDs).count
    return Set(
      slots.filter { slot in
        let layer = params.choice(slotLayerID(slot))
        return slot > offered && (layer.isEmpty || layer == "none")
      }.map(slotLayerID))
  }

  /// A slot picker's tokens: `none`, then the bundle's custom line layers; `nil` for any other
  /// parameter.
  package static func slotOptions(for spec: ParamSpec, planes: [String: Int]) -> [String]? {
    guard slots.contains(where: { slotLayerID($0) == spec.id }) else { return nil }
    return ["none"] + customLayers(in: planes.keys)
  }

  /// One « Other line » card, the builder both line processes share.
  ///
  /// The slot's layer parameter, then `rows` of its line except the ids ending in `without` (the
  /// continuum ones), each about the layer the slot names.
  static func slotSpecs(
    _ slot: Int, rows: (Self) -> [ParamSpec], without: Set<String>
  ) -> [ParamSpec] {
    let line = custom(slot: slot, layer: "none")
    let excluded = Set(without.map(line.id))
    return [slotLayerSpec(slot)]
      + rows(line).filter { !excluded.contains($0.id) }.map { $0.about(layerIn: slotLayerID(slot)) }
  }

  /// Refuses what `lines` cannot read honestly: a slot naming a layer that is not a custom line
  /// (a broadband layer, a catalogued line — values from a recipe the picker never offered), or
  /// two lines on one layer (added twice by accident).
  package static func checkBound(_ lines: [Self]) throws {
    var seen: [String: Self] = [:]
    for line in lines {
      if line.filter == nil, customLayers(in: [line.layerID]).isEmpty {
        throw ProcessError.invalidParameter(
          "\(line.name) reads the \(line.layerID) layer, which is not a line outside the catalogue")
      }
      if let first = seen[line.layerID] {
        throw ProcessError.invalidParameter(
          "\(line.name) reads the \(line.layerID) layer, already read by \(first.name)")
      }
      seen[line.layerID] = line
    }
  }
}
