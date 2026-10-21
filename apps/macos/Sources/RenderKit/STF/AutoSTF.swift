/// Siril's autostretch parameters, computed from each plane's median and MAD.
///
/// Per channel (Siril `find_unlinked_midtones_balance`): MADN = 1.4826 · MAD; c0 = median +
/// shadowsClip · MADN clamped to [0, 1]; m = MTF(target, median − c0), so the background lands on
/// `targetBackground`; c1 = 1. Linked: the same parameters for every channel, from the mean of the
/// channels' medians and MADNs. Medians are the upper median (`sorted[n/2]`).
package enum AutoSTF {
  /// MAD → standard deviation of a normal distribution.
  static let madToSigma = 1.4826

  /// The STF of each plane.
  package static func compute(
    planes: [[Float]], linked: Bool, shadowsClip: Double = -2.8, targetBackground: Double = 0.25
  ) -> [STFParameters] {
    let stats = planes.map(Self.medianAndMADN)
    if linked, !stats.isEmpty {
      let median = stats.map(\.median).reduce(0, +) / Double(stats.count)
      let madn = stats.map(\.madn).reduce(0, +) / Double(stats.count)
      let shared = parameters(median: median, madn: madn, shadowsClip, targetBackground)
      return Array(repeating: shared, count: planes.count)
    }
    return stats.map { parameters(median: $0.median, madn: $0.madn, shadowsClip, targetBackground) }
  }

  private static func parameters(
    median: Double, madn: Double, _ shadowsClip: Double, _ target: Double
  ) -> STFParameters {
    let shadows = min(max(median + shadowsClip * madn, 0), 1)
    // The midtone m with MTF(m, median − c0) = target is MTF(target, median − c0): the MTF is
    // its own inverse in this sense.
    let midtone = min(max(MTF.apply(target, median - shadows), 0), 1)
    return STFParameters(shadows: shadows, midtone: midtone, highlights: 1)
  }

  /// Upper median and normalised MAD of a plane's finite values (NaN/Inf blanks left out; a
  /// 64 Ki-sample stride above that size).
  package static func medianAndMADN(_ plane: [Float]) -> (median: Double, madn: Double) {
    let stride = max(1, plane.count / 65_536)
    let sample = Swift.stride(from: 0, to: plane.count, by: stride)
      .map { Double(plane[$0]) }.filter(\.isFinite)
    guard !sample.isEmpty else { return (0, 0) }
    let median = upperMedian(sample)
    let mad = upperMedian(sample.map { abs($0 - median) })
    return (median, mad * madToSigma)
  }

  private static func upperMedian(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    return sorted[sorted.count / 2]
  }
}
