/// The pixel "curve" of one frame (`frameStat`): robust summaries of its centre sample.
package struct FrameStat: Equatable, Sendable {
  package var exposureMs: Int
  package var median: Double
  /// Median absolute deviation: robust noise.
  package var mad: Double
  /// Fraction of pixels above median + 3·MAD: structure, nebulosity.
  package var brightFraction: Double
  /// Local maxima above median + 6·MAD: stars and hot pixels.
  package var peaks: Int
  /// The curve was measured.
  ///
  /// An unmeasured all-zero curve looks like a bias at the floor and must never be classified from
  /// (the legacy engine's phantom-BIAS bug).
  package var measured: Bool

  /// A curve; `measured: false` for a frame whose pixels could not be read.
  package init(
    exposureMs: Int, median: Double = 0, mad: Double = 0, brightFraction: Double = 0,
    peaks: Int = 0, measured: Bool = true
  ) {
    self.exposureMs = exposureMs
    self.median = median
    self.mad = mad
    self.brightFraction = brightFraction
    self.peaks = peaks
    self.measured = measured
  }
}
