/// How Siril combines a stack: the legacy `stackalg.Options` (combine, rejection, normalization,
/// weighting), rendered by `StackClause`.
package struct StackOptions: Equatable, Sendable {
  /// The pixel combination.
  package enum Combine: String, CaseIterable, Sendable {
    case mean, median, sum, max, min

    /// Siril's token (`rej` for a rejecting mean).
    var token: String { self == .mean ? "rej" : self == .median ? "med" : rawValue }
    /// Mean and median normalize; sum, max and min take nothing else.
    var normalizes: Bool { self == .mean || self == .median }
    /// Only the mean rejects.
    var rejects: Bool { self == .mean }
  }

  /// The rejection algorithm; `.auto` picks one from the frame count.
  package enum Rejection: CaseIterable, Sendable {
    case auto, none, percentile, sigma, medianSigma, winsorized, linearFit, gesd, mad
  }

  /// Input normalization; `.auto` is Siril's additive + scaling.
  package enum Normalization: String, CaseIterable, Sendable {
    case auto, none, add, mul, addscale, mulscale
  }

  /// Pixel combination.
  package var combine: Combine
  /// Rejection algorithm.
  package var rejection: Rejection
  /// Low parameter; 0 takes the algorithm's default, others are clamped to its range.
  package var low: Double
  /// High parameter; 0 takes the algorithm's default.
  package var high: Double
  /// Input normalization.
  package var normalization: Normalization
  /// `-fastnorm`.
  package var fastNormalization: Bool
  /// `-output_norm`.
  package var outputNormalization: Bool
  /// `-weight=<w>` (`wfwhm`, `noise`…), none when `nil`.
  package var weight: String?
  /// `-rejmaps`.
  package var rejectionMaps: Bool
  /// `-feather=<px>` when > 0.
  package var featherPx: Int

  /// Options; every field defaults to the legacy zero value.
  package init(
    combine: Combine = .mean, rejection: Rejection = .auto, low: Double = 0, high: Double = 0,
    normalization: Normalization = .auto, fastNormalization: Bool = false,
    outputNormalization: Bool = false, weight: String? = nil, rejectionMaps: Bool = false,
    featherPx: Int = 0
  ) {
    self.combine = combine
    self.rejection = rejection
    self.low = low
    self.high = high
    self.normalization = normalization
    self.fastNormalization = fastNormalization
    self.outputNormalization = outputNormalization
    self.weight = weight
    self.rejectionMaps = rejectionMaps
    self.featherPx = featherPx
  }

  /// Lights (`DefaultLights` + `Weight = wfwhm`): mean, auto rejection, additive + scaling.
  package static let lights = Self(
    normalization: .addscale, outputNormalization: true, weight: "wfwhm")
  /// Bias masters: mean, auto rejection, no normalization.
  package static let bias = Self(normalization: .none)
  /// Dark masters: as bias.
  package static let dark = Self(normalization: .none)
  /// Flat masters: multiplicative normalization.
  package static let flat = Self(normalization: .mul)
}
