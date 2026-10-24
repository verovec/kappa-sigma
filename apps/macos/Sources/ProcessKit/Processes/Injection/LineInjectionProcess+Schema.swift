extension LineInjectionProcess {
  /// One card per line in `EmissionLine` order: gain, continuum scale k, black point, shares.
  package static let schema = ParamSchema(EmissionLine.allCases.flatMap(lineSpecs))

  /// One line's card; the gains default to 0 (the identity), the shares to the line's colour.
  private static func lineSpecs(_ line: EmissionLine) -> [ParamSpec] {
    let name = line.name
    let shares = defaultShares(line)
    return [
      ParamSpec(
        id: line.id("Gain"), title: name + " gain", unit: .none, level: .simple, number: 0,
        in: 0...4),
      ParamSpec(
        id: line.id("ContinuumK"), title: name + " continuum scale k", unit: .none,
        level: .simple, number: 0, in: 0...5),
      ParamSpec(
        id: line.id("Black"), title: name + " black point", unit: .none, level: .advanced,
        number: 0, in: 0...1),
    ]
      + zip(shareSuffixes, shares).map { plane, share in
        ParamSpec(
          id: line.id(plane), title: name + " into " + plane.lowercased(), unit: .opacity,
          level: .advanced, number: share, in: 0...1)
      }
  }

  /// Hα and [SII] go into red; [OIII] into green and blue, half each.
  private static func defaultShares(_ line: EmissionLine) -> [Double] {
    switch line {
    case .hydrogenAlpha, .sulfurII: [1, 0, 0]
    case .oxygenIII: [0, 0.5, 0.5]
    }
  }

  /// The reasons the panel shows next to a suggestion: English keys of the catalog.
  ///
  /// The first is the emission screens' own, for a reference plane this list does not name.
  package static let suggestionReasons = [
    "the continuum scale fitted on the stack",
    "the continuum scale fitted on the stack against the L layer",
    "the continuum scale fitted on the stack against the R layer",
    "the continuum scale fitted on the stack against the G layer",
    "the continuum scale fitted on the stack against the B layer",
    "the continuum scale fitted on the stack against the colour base's red plane",
    "the continuum scale fitted on the stack against the colour base's green plane",
    "the continuum scale fitted on the stack against the colour base's blue plane",
  ]

  /// The broadband layers a continuum is fitted against, in the canonical filter order (pinned
  /// against StackKit's `Filter` by the tests: ProcessKit cannot import it), as `EmissionLine` is.
  package static let broadbandLayers = ["L", "R", "G", "B"]

  /// The reason naming the plane `reference` (a `LayerPlane` token: `R`, `RGB.r`…) k was fitted
  /// against: what the user needs to judge it.
  package static func continuumReason(reference: String) -> String {
    let plane = LayerPlane(reference)
    let index: Int? =
      plane.token == plane.layer
      ? broadbandLayers.firstIndex(of: plane.layer).map { $0 + 1 }
      : plane.plane + 5
    return suggestionReasons[index ?? 0]
  }

  /// The fitted continuum scale of every line whose bundle layer carries one with its reference
  /// plane, inside the schema's range as the emission screens offer it (the suggested value is
  /// the one applied); never applied by the process (R2).
  package func suggestions(stats: LayerStats, layers: [String: LayerStats]) -> [Suggestion] {
    // Only for a line that injects, as the screens offer k only for an enabled line.
    EmissionLine.allCases.compactMap { line in
      guard Self.injects(line, params: params), let fit = line.continuumFit(in: layers),
        case .number(_, let bounds)? = Self.schema.spec(line.id("ContinuumK"))?.kind
      else { return nil }
      return Suggestion(
        paramID: line.id("ContinuumK"),
        value: .number(min(max(fit.k, bounds.lowerBound), bounds.upperBound)),
        reason: Self.continuumReason(reference: fit.reference))
    }
  }
}
