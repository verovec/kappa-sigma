internal import FilterKit

/// A channel-combination preset: which layer feeds each slot.
///
/// From the legacy `docs/architecture.md` palette table. Pure slot templates: weights and black
/// points stay as the user set them.
package enum Palette: String, CaseIterable, Sendable {
  /// One-shot colour: the OSC base planes as they are.
  case natural
  /// Bicolour: Hα, OIII, OIII.
  case hoo
  /// Hubble: SII, Hα, OIII.
  case sho
  /// CFHT: Hα, OIII, SII.
  case hos
  /// Webb-style: Hα, √(Hα·OIII), OIII.
  case foraxx
  /// Mono filters: R, G, B, with L as luminance.
  case lrgb
  /// Mono filters: R, G, B, no luminance.
  case rgb

  /// The name the panel and the reasons use.
  package var title: String {
    switch self {
    case .natural: "Natural"
    case .hoo: "HOO"
    case .sho: "SHO"
    case .hos: "HOS"
    case .foraxx: "Foraxx"
    case .lrgb: "LRGB"
    case .rgb: "RGB"
    }
  }

  /// The palette a bundle's layers spell (card 0138): lrgb / rgb on R, G, B (with L or not),
  /// sho on the three lines, hoo on Hα + OIII; none for a colour layer or anything else.
  package static func spelled(by layerIDs: Set<String>) -> Self? {
    let ids = Set(layerIDs.compactMap(Filter.init(rawValue:)))
    if ids.isSuperset(of: [.red, .green, .blue]) { return ids.contains(.luminance) ? .lrgb : .rgb }
    if ids.isSuperset(of: [.sulfurII, .hydrogenAlpha, .oxygenIII]) { return .sho }
    if ids.isSuperset(of: [.hydrogenAlpha, .oxygenIII]) { return .hoo }
    return nil
  }

  /// Sources of the R, G, B and L slots, in that order.
  package var sources: [String] {
    switch self {
    case .natural: ["RGB.r", "RGB.g", "RGB.b", "none"]
    case .hoo: ["Ha", "OIII", "OIII", "none"]
    case .sho: ["SII", "Ha", "OIII", "none"]
    case .hos: ["Ha", "OIII", "SII", "none"]
    case .foraxx: ["Ha", "Ha*OIII", "OIII", "none"]
    case .lrgb: ["R", "G", "B", "L"]
    case .rgb: ["R", "G", "B", "none"]
    }
  }

  /// The layer ids the sources read, once each, in slot order.
  package var layers: [String] {
    var ids: [String] = []
    for source in sources where source != "none" {
      for part in source.split(separator: "*") {
        let id = LayerPlane(String(part)).layer
        if !ids.contains(id) { ids.append(id) }
      }
    }
    return ids
  }

  /// The palettes a bundle of `planes` offers (card 0139), in catalogue order: those whose every
  /// source the bundle names (`LayerPlane.options`: a plane needs a colour layer, a product two
  /// 1-plane lines).
  package static func available(planes: [String: Int]) -> [Self] {
    let offered = Set(LayerPlane.options(planes: planes, allowsNone: true, allowsProduct: true))
    return allCases.filter { $0.sources.allSatisfy(offered.contains) }
  }

  /// The combination's default values with this palette's sources.
  package func params() throws -> ParamSet {
    try apply(to: ParamSet(schema: ChannelCombinationProcess.schema))
  }

  /// `params` with this palette's sources; weights, black points and L opacity are kept.
  package func apply(to params: ParamSet) throws -> ParamSet {
    var params = params
    try ChannelCombinationProcess.set(sources: sources, on: &params)
    return params
  }

  /// The palette whose sources `params` has, or `nil` for a custom combination.
  package static func matching(_ params: ParamSet) -> Self? {
    let current = ChannelCombinationProcess.slotSources.map { params.choice($0) }
    return allCases.first { $0.sources == current }
  }
}
