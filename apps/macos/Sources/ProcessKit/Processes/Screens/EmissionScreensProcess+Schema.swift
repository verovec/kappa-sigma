extension EmissionScreensProcess {
  /// The global parameters, then one card per line in `EmissionLine` order.
  package static let schema: ParamSchema = {
    var specs = [
      ParamSpec(
        id: "nbBlend", title: "Narrowband blend", unit: .opacity, level: .simple, number: 1,
        in: 0...1),
      ParamSpec(
        id: "starRadius", title: "Star removal radius", unit: .px, level: .simple, number: 4,
        in: 0...32),
      ParamSpec(
        id: "smooth", title: "Layer smoothing", unit: .px, level: .advanced, number: 0, in: 0...32),
      ParamSpec(
        id: "shadowsClip", title: "Shadows clip", unit: .sigma, level: .advanced, number: -2.5,
        in: -10...0),
      ParamSpec(id: "linkLayers", title: "Link layers", level: .advanced, flag: false),
    ]
    for line in EmissionLine.allCases { specs += lineSpecs(line) }
    return ParamSchema(specs)
  }()

  /// One line's card: on/off, continuum subtraction, stretch, black point, screen.
  private static func lineSpecs(_ line: EmissionLine) -> [ParamSpec] {
    let name = line.name
    return [
      ParamSpec(
        id: line.id("Enabled"), title: name + " screen", level: .simple,
        flag: line.defaults.enabled),
      ParamSpec(
        id: line.id("Continuum"), title: name + " continuum subtraction", level: .simple,
        flag: false),
      ParamSpec(
        id: line.id("ContinuumK"), title: name + " continuum scale k", unit: .none,
        level: .advanced, number: 0, in: 0...5),
      ParamSpec(
        id: line.id("Background"), title: name + " background", unit: .none, level: .simple,
        number: 0.12, in: 0.01...0.6),
      ParamSpec(
        id: line.id("Black"), title: name + " black point", unit: .none, level: .simple,
        number: 0, in: 0...0.9),
      ParamSpec(
        id: line.id("Opacity"), title: name + " opacity", unit: .opacity, level: .simple,
        number: line.defaults.opacity, in: 0...1),
      ParamSpec(
        id: line.id("Tint"), title: name + " tint", level: .simple,
        choice: line.defaults.tint.rawValue, of: ScreenTint.allCases.map(\.rawValue)),
      ParamSpec(
        id: line.id("Boost"), title: name + " boost", unit: .none, level: .advanced, number: 1,
        in: 1...3),
    ]
  }
}
