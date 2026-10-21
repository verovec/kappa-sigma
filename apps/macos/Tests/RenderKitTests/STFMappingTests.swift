import RenderKit
import Testing

/// `STFMapping`: shadows in σ of the MADN around the median, the target background behind the
/// midtone — the one mapping `AutoSTF` and the stretch controls share (card 0085).
@Suite("STFMapping — shadows in σ, target background, pinned to Siril's autostretch")
struct STFMappingTests {
  /// Recorded plane statistics: a dark sky, a bright one, a flat frame, a linked mean.
  struct Stats: Sendable, CustomTestStringConvertible {
    let median: Double
    let madn: Double
    var testDescription: String { "median \(median), MADN \(madn)" }
    var mapping: STFMapping { STFMapping(median: median, madn: madn) }
  }

  nonisolated static let recorded = [
    Stats(median: 0.011_72, madn: 0.001_48), Stats(median: 0.1, madn: 0.014_826),
    Stats(median: 0.42, madn: 0.03), Stats(median: 0.005, madn: 0.000_31),
  ]

  /// Planes whose statistics span the recorded ones (a ramp, noise, a near-flat sky).
  nonisolated static let planes: [[Float]] = [
    (0..<1001).map { Float($0) / 1000 },
    (0..<2048).map { Float(($0 &* 2_654_435_761) % 1000) / 50_000 + 0.01 },
    (0..<301).map { 0.1 + Float($0 % 7) / 1000 },
  ]

  @Test("σ → c0 → σ round-trips while c0 stays inside [0, 1]", arguments: recorded)
  func testSigmaRoundTrip(_ stats: Stats) {
    let mapping = stats.mapping
    for sigma in stride(from: -5.0, through: 5.0, by: 0.5) {
      let shadows = mapping.shadows(sigma: sigma)
      let unclamped = stats.median + sigma * stats.madn
      if (0...1).contains(unclamped) {
        #expect(abs(mapping.sigma(ofShadows: shadows) - sigma) < 1e-9)
      } else {
        #expect(shadows == min(max(unclamped, 0), 1), "clamped like the autostretch")
      }
    }
  }

  @Test("target → m → target round-trips for a given black point", arguments: recorded)
  func testTargetRoundTrip(_ stats: Stats) {
    let mapping = stats.mapping
    let shadows = mapping.shadows(sigma: -2.8)
    for target in stride(from: 0.01, through: 0.6, by: 0.01) {
      let midtone = mapping.midtone(targetBackground: target, shadows: shadows)
      #expect(abs(mapping.targetBackground(ofMidtone: midtone, shadows: shadows) - target) < 1e-9)
      // Siril's meaning: MTF(m, median − c0) lands on the target (not rescaled by c1 − c0).
      #expect(abs(MTF.apply(midtone, stats.median - shadows) - target) < 1e-9)
    }
  }

  @Test("−2.8 σ / 0.25 equals AutoSTF.compute bit for bit, linked and per channel")
  func testSigmaRoundTripMatchesAutoSTF() {
    for linked in [false, true] {
      let mappings = STFMapping.measure(planes: Self.planes, linked: linked)
      let auto = AutoSTF.compute(planes: Self.planes, linked: linked)
      #expect(mappings.count == Self.planes.count)
      for (mapping, expected) in zip(mappings, auto) {
        let computed = mapping.parameters(sigma: -2.8, targetBackground: 0.25)
        #expect(computed == expected)
        #expect(computed.shadows.bitPattern == expected.shadows.bitPattern)
        #expect(computed.midtone.bitPattern == expected.midtone.bitPattern)
        // And back: the controls read the autostretch as −2.8 σ at 0.25 — or, when the clip
        // landed below 0 and c0 was clamped, as the σ of c0 = 0 (a dark plane).
        let readBack = mapping.sigma(ofShadows: expected.shadows)
        let clamped = mapping.median - 2.8 * mapping.madn < 0
        #expect(abs(readBack - (clamped ? -mapping.median / mapping.madn : -2.8)) < 1e-9)
        #expect(
          abs(
            mapping.targetBackground(ofMidtone: expected.midtone, shadows: expected.shadows) - 0.25)
            < 1e-9)
      }
    }
    let linked = STFMapping.measure(planes: Self.planes, linked: true)
    #expect(linked.allSatisfy { $0 == linked[0] }, "linked: one mapping for every channel")
  }

  @Test("a flat plane (MADN 0) reads every black point as 0 σ and stays finite")
  func testFlatPlane() {
    let mapping = STFMapping(median: 0.3, madn: 0)
    #expect(mapping.sigma(ofShadows: 0.2) == 0)
    #expect(mapping.shadows(sigma: -2.8) == 0.3)
    let midtone = mapping.midtone(targetBackground: 0.25, shadows: 0.3)
    #expect(midtone.isFinite && (0...1).contains(midtone))
  }
}
