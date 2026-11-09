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
    let stride = sampleStride(count: plane.count)
    return sampleMedianAndMADN(Swift.stride(from: 0, to: plane.count, by: stride).map { plane[$0] })
  }

  /// The stride `medianAndMADN` samples a plane of `count` values with: every value up to 64 Ki,
  /// then one in `count / 65 536` — the rule a GPU-gathered sample follows (card 0188).
  package static func sampleStride(count: Int) -> Int {
    max(1, count / 65_536)
  }

  /// Upper median and normalised MAD of the finite values of `sample`, already strided.
  package static func sampleMedianAndMADN(_ sample: [Float]) -> (median: Double, madn: Double) {
    let finite = sample.map { Double($0) }.filter(\.isFinite)
    guard !finite.isEmpty else { return (0, 0) }
    let median = upperMedian(finite)
    let mad = upperMedian(finite.map { abs($0 - median) })
    return (median, mad * madToSigma)
  }

  private static func upperMedian(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    return sorted[sorted.count / 2]
  }
}
