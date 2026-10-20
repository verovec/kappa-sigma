/// A frame's tonal distribution (`photom.FrameCurve`): 14 probe percentiles from the sky to the
/// star-saturation shoulder, the background level and a noise estimate.
package struct FrameCurve: Equatable, Sendable {
  /// The probe percentiles; indices 12 and 13 (P99, P99.5) track saturation and stay out of fits.
  package static let percentiles: [Double] = [
    5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 97.5, 99, 99.5,
  ]
  /// The background probe.
  ///
  /// Index 3 is P30 (the legacy comment says P40; the code is the oracle).
  static let backgroundIndex = 3
  /// At most this many pixels feed the estimators.
  static let sampleLimit = 200_000
  static let madToSigma = 1.4826
  /// The calibrated level above which a pixel is sensor-saturated (`SatDetectLevel`).
  package static let saturationLevel: Float = 0.97

  /// The values at the probe `percentiles`.
  package var quantiles = [Double](repeating: 0, count: 14)
  package var background = 0.0
  /// 1.4826 × MAD of the sample.
  package var noise = 0.0
  /// The sampled fraction at or above `saturationLevel`.
  package var saturatedFraction = 0.0

  /// A curve from its parts.
  package init(
    quantiles: [Double] = .init(repeating: 0, count: 14), background: Double = 0,
    noise: Double = 0
  ) {
    self.quantiles = quantiles
    self.background = background
    self.noise = noise
  }

  /// The curve of an image (`MeasureImage`): plane 0, or the per-pixel mean of up to three planes,
  /// strided down to `sampleLimit` pixels.
  package init(planes: [[Float]]) {
    self.init(
      sample: PhotomStats.subsample(PhotomStats.sampleSlice(planes), limit: Self.sampleLimit))
  }

  /// The curve of a pre-collected sample (`curveOf`).
  package init(sample: [Float]) {
    self.init()
    let sorted = sample.map(Double.init).sorted()
    quantiles = Self.percentiles.map { PhotomStats.percentile(sorted: sorted, $0) }
    background = quantiles[Self.backgroundIndex]
    noise = Self.madToSigma * PhotomStats.mad(sample)
    if !sample.isEmpty {
      saturatedFraction = Double(sample.count { $0 >= Self.saturationLevel }) / Double(sample.count)
    }
  }

  /// The component-wise median of `curves` (`medianCurve`; saturation is not carried, as in Go).
  package static func median(_ curves: [Self]) -> Self {
    var out = Self()
    for index in percentiles.indices {
      out.quantiles[index] = PhotomStats.median(curves.map { $0.quantiles[index] })
    }
    out.background = PhotomStats.median(curves.map(\.background))
    out.noise = PhotomStats.median(curves.map(\.noise))
    return out
  }
}
