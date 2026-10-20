/// The options of a `stack` command, as `stackclause.go` renders them.
///
/// Order: rejection clause; normalization (`-nonorm` / `-norm=`) and `-fastnorm` when the combine
/// normalizes; `-output_norm`; `-weight=` and `-rejmaps` when it rejects; `-feather=`.
package enum StackClause {
  /// One rejection algorithm's Siril token and parameter defaults and range (`catalogue.go`).
  struct Algorithm {
    let token: String
    let low: (default: Double, min: Double, max: Double)
    let high: (default: Double, min: Double, max: Double)
  }

  /// ≤ 7 frames: percentile; ≥ 50: GESD; otherwise (and for ≤ 0): winsorized.
  static func auto(frames: Int) -> StackOptions.Rejection {
    if frames > 0 && frames <= 7 { return .percentile }
    return frames >= 50 ? .gesd : .winsorized
  }

  static func algorithm(_ rejection: StackOptions.Rejection) -> Algorithm? {
    let sigma = (default: 3.0, min: 0.5, max: 10.0)
    switch rejection {
    case .auto, .none: return nil
    case .percentile:
      return Algorithm(token: "percentile", low: (0.2, 0.01, 0.9), high: (0.1, 0.01, 0.9))
    case .sigma: return Algorithm(token: "sigma", low: sigma, high: sigma)
    case .medianSigma: return Algorithm(token: "median", low: sigma, high: sigma)
    case .winsorized: return Algorithm(token: "winsorized", low: sigma, high: sigma)
    case .linearFit:
      return Algorithm(token: "linear", low: (5, 0.5, 10), high: (3.5, 0.5, 10))
    case .gesd:
      return Algorithm(token: "generalized", low: (0.3, 0.01, 0.9), high: (0.05, 0.001, 0.5))
    case .mad: return Algorithm(token: "mad", low: sigma, high: sigma)
    }
  }

  /// The clause for `options` stacking `frames` frames.
  package static func render(_ options: StackOptions, frames: Int) -> String {
    var parts = [rejectionClause(options, frames: frames)]
    let combine = options.combine
    if combine.normalizes {
      switch options.normalization {
      case .none: parts.append("-nonorm")
      case .auto: parts.append("-norm=addscale")
      default: parts.append("-norm=\(options.normalization.rawValue)")
      }
      if options.fastNormalization { parts.append("-fastnorm") }
      if options.outputNormalization { parts.append("-output_norm") }
    }
    if combine.rejects {
      if let weight = options.weight, !weight.isEmpty { parts.append("-weight=\(weight)") }
      if options.rejectionMaps { parts.append("-rejmaps") }
    }
    if options.featherPx > 0 { parts.append("-feather=\(options.featherPx)") }
    return parts.joined(separator: " ")
  }

  private static func rejectionClause(_ options: StackOptions, frames: Int) -> String {
    guard options.combine.rejects else { return options.combine.token }
    let isAuto = options.rejection == .auto
    let rejection = isAuto ? auto(frames: frames) : options.rejection
    guard let algorithm = algorithm(rejection) else { return "rej none" }
    // An auto choice drops any explicit parameters: they belonged to another algorithm.
    let low = resolve(isAuto ? 0 : options.low, algorithm.low)
    let high = resolve(isAuto ? 0 : options.high, algorithm.high)
    return "rej \(algorithm.token) \(GoFormat.shortest(low)) \(GoFormat.shortest(high))"
  }

  /// ≤ 0 takes the default; anything else is clamped to the range.
  private static func resolve(_ value: Double, _ param: (default: Double, min: Double, max: Double))
    -> Double
  {
    value <= 0 ? param.default : min(max(value, param.min), param.max)
  }
}
