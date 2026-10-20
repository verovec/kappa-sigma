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

  /// The name the panel and the reasons use.
  package var title: String {
    switch self {
    case .natural: "Natural"
    case .hoo: "HOO"
    case .sho: "SHO"
    case .hos: "HOS"
    case .foraxx: "Foraxx"
    case .lrgb: "LRGB"
    }
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
    }
  }

  /// The combination's default values with this palette's sources.
  package func params() throws -> ParamSet {
    var params = ParamSet(schema: ChannelCombinationProcess.schema)
    try params.set("palette", .choice(rawValue))
    for (slot, source) in zip(["rSource", "gSource", "bSource", "lSource"], sources) {
      try params.set(slot, .choice(source))
    }
    return params
  }
}
