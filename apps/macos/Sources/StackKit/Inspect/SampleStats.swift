/// Robust summary of a contiguous pixel sample (`fits.summarize`): what the frame classifier and
/// wheel-order detection compare. Order statistics are taken by index (`sorted[n/2]`, the upper
/// middle), exactly as the legacy engine took them.
package struct SampleStats: Equatable, Sendable {
  package let count: Int
  package let mean: Double
  package let median: Double
  package let min: Double
  package let max: Double
  /// Median absolute deviation from the median.
  package let mad: Double
  /// 90th percentile: a robust bright-signal proxy.
  package let p90: Double
  /// Fraction of values above median + 3·MAD.
  package let brightFraction: Double
  /// Local maxima above median + 6·MAD along the run: stars and hot pixels.
  package let peaks: Int

  /// The summary of `values` in spatial order; `nil` for an empty sample.
  package init?(_ values: [Double]) {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let middle = values.count / 2
    let median = sorted[middle]
    let mad = sorted.map { abs($0 - median) }.sorted()[middle]
    let bright = median + 3 * mad
    count = values.count
    mean = values.reduce(0, +) / Double(values.count)
    self.median = median
    min = sorted[0]
    max = sorted[sorted.count - 1]
    self.mad = mad
    p90 = sorted[values.count * 9 / 10]
    brightFraction = Double(values.count { $0 > bright }) / Double(values.count)
    peaks = Self.peaks(values, above: median + 6 * mad)
  }

  /// Local maxima: a strict rise then a non-strict fall, the ends excluded.
  private static func peaks(_ values: [Double], above threshold: Double) -> Int {
    guard values.count > 2 else { return 0 }
    return (1..<values.count - 1).count { index in
      values[index] > threshold && values[index] > values[index - 1]
        && values[index] >= values[index + 1]
    }
  }

  /// The curve the frame classifier compares.
  package func frameStat(exposureMs: Int) -> FrameStat {
    FrameStat(
      exposureMs: exposureMs, median: median, mad: mad, brightFraction: brightFraction,
      peaks: peaks)
  }
}
