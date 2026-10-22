/// Siril's autostretch parameters, computed from each plane's median and MAD.
///
/// Per channel (Siril `find_unlinked_midtones_balance`): MADN = 1.4826 · MAD; c0 = median +
/// shadowsClip · MADN clamped to [0, 1]; m = MTF(target, median − c0), so the background lands on
/// `targetBackground`; c1 = 1. Linked: the same parameters for every channel, from the mean of the
/// channels' medians and MADNs. Medians are the upper median (`sorted[n/2]`). The arithmetic is
/// `STFMapping`'s: the stretch controls read an autostretch back as −2.8 σ at 0.25.
package enum AutoSTF {
  /// MAD → standard deviation of a normal distribution.
  static let madToSigma = 1.4826
  /// Siril's shadows clip, in σ of the MADN.
  package static let shadowsClip = -2.8
  /// Siril's target background.
  package static let targetBackground = 0.25

  /// The STF of each plane.
  package static func compute(
    planes: [[Float]], linked: Bool, shadowsClip: Double = shadowsClip,
    targetBackground: Double = targetBackground
  ) -> [STFParameters] {
    STFMapping.measure(planes: planes, linked: linked).map {
      $0.parameters(sigma: shadowsClip, targetBackground: targetBackground)
    }
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
