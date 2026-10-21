internal import Foundation

extension EmissionScreensProcess {
  /// The reasons the panel shows next to a suggestion: English keys of the catalog.
  package static let suggestionReasons = [
    "the continuum scale fitted on the stack",
    "a black point 3σ above zero hides the stretched sky noise",
  ]

  /// The stretch of every enabled line, from the bundle statistics; with `linkLayers`, every line
  /// takes the first one's (astrocomp `-link-layers`: the true amplitude ratio).
  package func lineStretches(layerStats: [String: LayerStats]) throws -> [EmissionLine:
    LineStretch]
  {
    var stretches: [EmissionLine: LineStretch] = [:]
    for line in enabledLines {
      if params.flag("linkLayers"), let first = enabledLines.first, let linked = stretches[first] {
        stretches[line] = linked
        continue
      }
      let (median, madn) = try linearStats(line, layerStats: layerStats)
      stretches[line] = try LineStretch(
        median: median, madn: madn, clip: params.number("shadowsClip"),
        target: params.number(line.id("Background")), name: line.name)
    }
    return stretches
  }

  /// The background median and MADN the stretch of `line` starts from: the bundle's, or, after a
  /// continuum subtraction, median − k · reference median and the two noises in quadrature.
  ///
  /// Derived, never measured on the subtracted layer (R2); the panel shows both.
  package func linearStats(
    _ line: EmissionLine, layerStats: [String: LayerStats]
  ) throws -> (median: Double, madn: Double) {
    guard let stats = layerStats[line.layerID]?.channels.first else {
      throw ProcessError.invalidParameter(
        "\(line.name): the bundle has no statistics for its layer")
    }
    guard params.flag(line.id("Continuum")) else { return (stats.median, stats.madn) }
    let token = try continuumReference(line, layerStats: layerStats)
    guard let reference = LayerPlane(token).stats(in: layerStats) else {
      throw ProcessError.invalidParameter(
        "\(line.name): the bundle has no statistics for the continuum reference \(token)")
    }
    let k = params.number(line.id("ContinuumK"))
    return (
      stats.median - k * reference.median,
      (stats.madn * stats.madn + k * k * reference.madn * reference.madn).squareRoot()
    )
  }

  /// The plane the bundle fitted `line`'s continuum scale against.
  func continuumReference(_ line: EmissionLine, layerStats: [String: LayerStats]) throws
    -> String
  {
    guard let token = layerStats[line.layerID]?.continuumReference else {
      throw ProcessError.invalidParameter(
        "\(line.name): the bundle has no continuum fit: turn the subtraction off")
    }
    return token
  }

  /// `line`'s black point in σ of its stretched background noise, from the bundle statistics
  /// (`LineStretch.stretchedNoise`): what the panel shows next to the value.
  package func blackInSigma(_ line: EmissionLine, layerStats: [String: LayerStats]) throws
    -> Double
  {
    guard let stretch = try lineStretches(layerStats: layerStats)[line] else {
      throw ProcessError.invalidParameter("\(line.name) screen is off")
    }
    return params.number(line.id("Black")) / stretch.stretchedNoise
  }

  /// Per enabled line with bundle statistics: the fitted continuum scale, and a black point at
  /// 3σ of the stretched noise. None is applied by the process.
  package func suggestions(stats: LayerStats, layers: [String: LayerStats]) -> [Suggestion] {
    let reasons = Self.suggestionReasons
    var suggestions: [Suggestion] = []
    let stretches = (try? lineStretches(layerStats: layers)) ?? [:]
    for line in enabledLines {
      if let k = layers[line.layerID]?.continuumK {
        suggestions.append(
          Suggestion(paramID: line.id("ContinuumK"), value: .number(k), reason: reasons[0]))
      }
      if let stretch = stretches[line] {
        let black = min(3 * stretch.stretchedNoise, 0.9)
        suggestions.append(
          Suggestion(paramID: line.id("Black"), value: .number(black), reason: reasons[1]))
      }
    }
    return suggestions
  }
}
