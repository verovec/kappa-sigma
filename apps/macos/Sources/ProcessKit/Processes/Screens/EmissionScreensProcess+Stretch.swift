internal import Foundation

extension EmissionScreensProcess {
  /// The reasons the panel shows next to a suggestion: English keys of the catalog.
  package static let suggestionReasons = [
    "the continuum scale fitted on the stack",
    "a black point 3σ above zero hides the stretched sky noise",
  ]

  /// The stretch of every enabled line, from the bundle statistics.
  package func lineStretches(layerStats: [String: LayerStats]) throws -> [EmissionLine:
    LineStretch]
  {
    var stretches: [EmissionLine: LineStretch] = [:]
    for line in enabledLines { stretches[line] = try lineStretch(line, layerStats: layerStats) }
    return stretches
  }

  /// The stretch of `line`; with `linkLayers`, the first enabled line's curve (astrocomp
  /// `-link-layers`: the true amplitude ratio) over this line's own background.
  package func lineStretch(_ line: EmissionLine, layerStats: [String: LayerStats]) throws
    -> LineStretch
  {
    let (median, madn) = try linearStats(line, layerStats: layerStats)
    if params.flag("linkLayers"), let first = enabledLines.first, first != line {
      return try lineStretch(first, layerStats: layerStats).linked(median: median, madn: madn)
    }
    return try LineStretch(
      median: median, madn: madn, clip: params.number("shadowsClip"),
      target: params.number(line.id("Background")), name: line.name)
  }

  /// The background median and MADN the stretch of `line` starts from: the bundle's, or, after a
  /// continuum subtraction, median − k · reference median and the two noises in quadrature.
  ///
  /// Derived, never measured on the subtracted layer (R2); the panel shows both. A k that takes
  /// the background to 0 or below is refused: the clamped layer would have no sky to stretch.
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
    let median = stats.median - k * reference.median
    guard median > 0 else {
      throw ProcessError.invalidParameter(
        "\(line.name): k = \(k) subtracts the whole background (\(stats.median) − k × "
          + "\(reference.median) ≤ 0): lower k")
    }
    return (
      median, (stats.madn * stats.madn + k * k * reference.madn * reference.madn).squareRoot()
    )
  }

  /// The plane the bundle fitted the continuum scale of `line` against.
  func continuumReference(_ line: EmissionLine, layerStats: [String: LayerStats]) throws
    -> String
  {
    guard let token = layerStats[line.layerID]?.continuumReference else {
      throw ProcessError.invalidParameter(
        "\(line.name): the bundle has no continuum fit: turn the subtraction off")
    }
    return token
  }

  /// The black point of `line` in σ of its stretched background noise.
  ///
  /// From the bundle statistics (`LineStretch.stretchedNoise`): what the panel shows next to the
  /// value.
  package func blackInSigma(_ line: EmissionLine, layerStats: [String: LayerStats]) throws
    -> Double
  {
    guard enabledLines.contains(line) else {
      throw ProcessError.invalidParameter("\(line.name) screen is off")
    }
    let noise = try lineStretch(line, layerStats: layerStats).stretchedNoise
    guard noise > 0 else {
      throw ProcessError.invalidParameter(
        "\(line.name): the background is below the linked shadows, so it has no noise to count σ in"
      )
    }
    return params.number(line.id("Black")) / noise
  }

  /// The fitted continuum scale and a 3σ black point of every enabled line.
  ///
  /// From the bundle statistics, each line on its own (one line's refusal costs only its own
  /// suggestions); none is applied by the process.
  package func suggestions(stats: LayerStats, layers: [String: LayerStats]) -> [Suggestion] {
    let reasons = Self.suggestionReasons
    var suggestions: [Suggestion] = []
    for line in enabledLines {
      if let fit = line.continuumFit(in: layers),
        case .number(_, let bounds)? = Self.schema.spec(line.id("ContinuumK"))?.kind
      {
        let value = min(max(fit.k, bounds.lowerBound), bounds.upperBound)
        suggestions.append(
          Suggestion(paramID: line.id("ContinuumK"), value: .number(value), reason: reasons[0]))
      }
      if let noise = try? lineStretch(line, layerStats: layers).stretchedNoise, noise > 0 {
        suggestions.append(
          Suggestion(
            paramID: line.id("Black"), value: .number(min(3 * noise, 0.9)), reason: reasons[1]))
      }
    }
    return suggestions
  }
}
