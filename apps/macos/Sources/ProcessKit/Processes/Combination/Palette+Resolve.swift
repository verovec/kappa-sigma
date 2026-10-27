internal import FilterKit

extension Palette {
  /// A palette resolved against the layers present (`palette.go` resolvePalette, card 0137).
  package struct Resolution: Equatable, Sendable {
    /// The palette whose layers are all present; nil when none is: the image is then mono.
    package let palette: Palette?
    /// The one layer a mono image is made of (`Filter.monoSource`); nil when a palette resolves.
    package let monoSource: String?
    /// Why the requested palette was not kept, shown as a suggestion; nil when it was.
    package let reason: String?
  }

  /// The palette tried when one of this one's layers is missing (`palette.go` Fallback): a line
  /// palette falls to the bicolour, the bicolour to the broadband; the broadband templates (a
  /// colour layer, mono filters with L, without) try each other before the chain ends mono.
  var fallback: Palette {
    switch self {
    case .sho, .hos, .foraxx: .hoo
    case .hoo, .rgb: .natural
    case .natural: .lrgb
    case .lrgb: .rgb
    }
  }

  /// The layers its sources read that `present` lacks, in slot order.
  func missing(from present: Set<String>) -> [String] {
    var missing: [String] = []
    for source in sources {
      for layer in ChannelCombinationProcess.layers(of: source)
      where !present.contains(layer) && !missing.contains(layer) {
        missing.append(layer)
      }
    }
    return missing
  }

  /// `requested` if `present` has every layer it reads, else the first palette of its fallback
  /// chain that does, else mono on `Filter.monoSource` — with the reason, never applied (R2).
  package static func resolve(requested: Palette, present: Set<String>) -> Resolution {
    var tried: [Palette] = []
    var candidate = requested
    while !tried.contains(candidate) {
      if candidate.missing(from: present).isEmpty {
        let reason =
          candidate == requested
          ? nil : requested.reason(present, outcome: candidate.title + " instead")
        return Resolution(palette: candidate, monoSource: nil, reason: reason)
      }
      tried.append(candidate)
      candidate = candidate.fallback
    }
    let mono = Filter.monoSource(in: present)
    let outcome = mono.map { "\($0) alone, in grey" } ?? "nothing to combine"
    return Resolution(
      palette: nil, monoSource: mono, reason: requested.reason(present, outcome: outcome))
  }

  /// « SHO needs the SII and OIII layers: LRGB instead ».
  private func reason(_ present: Set<String>, outcome: String) -> String {
    let missing = missing(from: present)
    let layers = missing.count == 1 ? "layer" : "layers"
    return "\(title) needs the \(missing.joined(separator: " and ")) \(layers): \(outcome)"
  }

  /// OIII offered for the blue slot when there is no B filter (`pipeline.go:816-836`).
  ///
  /// OIII (~500 nm) is blue-green, so R and G keep natural star colours while OIII brings the
  /// blue nebulosity. Offered, never applied by `resolve` (R2).
  package static func oiiiAsBlue(present: Set<String>) -> Suggestion? {
    guard !present.contains("B"), present.isSuperset(of: ["R", "G", "OIII"]) else { return nil }
    return Suggestion(
      paramID: "bSource", value: .choice("OIII"),
      reason: "No B layer: OIII (500 nm, blue-green) can stand in for blue")
  }
}
