/// Shadows in σ of the noise and the target background: the mapping between what the stretch
/// controls say and the `STFParameters` the display applies (card 0085).
///
/// Siril's autostretch is one point of it — −2.8 σ at a 0.25 target (`AutoSTF`) — so the controls
/// read an autostretch as those two numbers and reproduce it bit for bit. Display only (R2): the
/// mapping never touches the data.
package struct STFMapping: Equatable, Sendable {
  /// Upper median of the plane's finite values.
  package let median: Double
  /// 1.4826 · MAD: the noise as a σ.
  package let madn: Double

  /// A mapping around `median` with the noise `madn`.
  package init(median: Double, madn: Double) {
    self.median = median
    self.madn = madn
  }

  /// One mapping per plane, or the mean of their statistics for every plane when `linked`.
  package static func measure(planes: [[Float]], linked: Bool) -> [Self] {
    let measured = planes.map(AutoSTF.medianAndMADN).map { Self(median: $0.median, madn: $0.madn) }
    return linked ? Self.linked(measured) : measured
  }

  /// The same mapping for every channel: the mean of their medians and MADNs.
  package static func linked(_ mappings: [Self]) -> [Self] {
    guard !mappings.isEmpty else { return mappings }
    let median = mappings.map(\.median).reduce(0, +) / Double(mappings.count)
    let madn = mappings.map(\.madn).reduce(0, +) / Double(mappings.count)
    return Array(repeating: Self(median: median, madn: madn), count: mappings.count)
  }

  /// c0 = median + σ·MADN, clamped to [0, 1].
  package func shadows(sigma: Double) -> Double {
    min(max(median + sigma * madn, 0), 1)
  }

  /// The σ with c0 = median + σ·MADN; 0 on a flat plane.
  package func sigma(ofShadows shadows: Double) -> Double {
    madn > 0 ? (shadows - median) / madn : 0
  }

  /// m with MTF(m, median − c0) = target, clamped to [0, 1].
  ///
  /// The MTF is its own inverse in this sense, so m = MTF(target, median − c0). Siril's meaning:
  /// median − c0 is not rescaled by c1 − c0.
  package func midtone(targetBackground target: Double, shadows: Double) -> Double {
    min(max(MTF.apply(target, median - shadows), 0), 1)
  }

  /// The level the median lands at through m: MTF(m, median − c0).
  package func targetBackground(ofMidtone midtone: Double, shadows: Double) -> Double {
    MTF.apply(midtone, median - shadows)
  }

  /// The stretch of (σ, target) with c1 = 1 — Siril's autostretch at −2.8 σ and 0.25.
  package func parameters(sigma: Double, targetBackground: Double) -> STFParameters {
    let shadows = shadows(sigma: sigma)
    return STFParameters(
      shadows: shadows, midtone: midtone(targetBackground: targetBackground, shadows: shadows),
      highlights: 1)
  }
}
