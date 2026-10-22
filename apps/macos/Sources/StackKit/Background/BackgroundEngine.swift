/// Which tool models the background, with the values it is given — applied as shown, never
/// clamped or cascaded (R2): a value outside the tool's range is refused by `validate()`.
package enum BackgroundEngine: Hashable, Sendable {
  /// GraXpert's AI model, `-smoothing` 0…1.
  case graxpert(smoothing: Double)
  /// Siril `subsky -rbf` (`SubskyRBFCmd`): smooth 0…1, samples per line ≥ 1, tolerance in σ ≥ 0.
  case sirilRBF(smooth: Double, samples: Int, tolerance: Double, dither: Bool)
  /// Siril `subsky <degree>`, a polynomial of degree 1…4.
  case sirilPolynomial(degree: Int)

  /// What runs for the engine: GraXpert with its smoothing, or Siril with one `subsky` command.
  package enum Tool: Equatable, Sendable {
    case graxpert(smoothing: Double)
    case siril(SirilCommand)
  }

  /// The tool and command of the engine.
  package var tool: Tool {
    switch self {
    case .graxpert(let smoothing): .graxpert(smoothing: smoothing)
    case .sirilRBF(let smooth, let samples, let tolerance, let dither):
      .siril(.subskyRBF(smooth: smooth, samples: samples, tolerance: tolerance, dither: dither))
    case .sirilPolynomial(let degree): .siril(.subsky(degree: degree))
    }
  }

  /// Whether the engine is GraXpert (else Siril).
  package var usesGraXpert: Bool {
    if case .graxpert = tool { return true }
    return false
  }

  /// Whether the engine applies `correction`: Siril's `subsky` only subtracts.
  package func supports(_ correction: BackgroundCorrection) -> Bool {
    usesGraXpert || correction == .subtract
  }

  /// The Siril command of a Siril engine; nil for GraXpert.
  package var sirilSubsky: SirilCommand? {
    if case .siril(let command) = tool { return command }
    return nil
  }

  /// The engine and its values, one line, for the cache key.
  package var cacheDescription: String {
    switch self {
    case .graxpert(let smoothing): "graxpert smoothing=\(smoothing)"
    case .sirilRBF(let smooth, let samples, let tolerance, let dither):
      "siril-rbf smooth=\(smooth) samples=\(samples) tolerance=\(tolerance) dither=\(dither)"
    case .sirilPolynomial(let degree): "siril-polynomial degree=\(degree)"
    }
  }

  /// Throws `BackgroundExtractionError.outOfRange` for a value the tool would refuse or clamp.
  package func validate() throws {
    switch self {
    case .graxpert(let smoothing):
      try Self.require("smoothing", smoothing, in: 0...1)
    case .sirilRBF(let smooth, let samples, let tolerance, _):
      try Self.require("smooth", smooth, in: 0...1)
      try Self.require("samples", Double(samples), in: 1...Double.infinity)
      try Self.require("tolerance", tolerance, in: 0...Double.infinity)
    case .sirilPolynomial(let degree):
      try Self.require("degree", Double(degree), in: 1...4)
    }
  }

  private static func require(_ name: String, _ value: Double, in range: ClosedRange<Double>)
    throws
  {
    guard range.contains(value) else {
      throw BackgroundExtractionError.outOfRange(
        parameter: name, value: value, lower: range.lowerBound, upper: range.upperBound)
    }
  }
}
