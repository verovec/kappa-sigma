import StackKit
import Testing

/// Translated from `internal/inspect/filterset_test.go` and the pure half of
/// `filtersetscan_test.go` (mosaic geometry, trimmed sky).
@Suite("FilterSetClassifier — dual-band or broadband, from the sky in electrons")
struct FilterSetClassifierTests {
  struct SkyCase: Sendable, CustomTestStringConvertible {
    let testDescription: String
    let sky: ChannelSky
    let exposureMs: Int
    let expected: FilterSet
  }

  static let skyCases: [SkyCase] = [
    SkyCase(testDescription: "dual-band at 120s", sky: ChannelSky(r: 6, g: 3, b: 2), exposureMs: 120_000, expected: .dualband),
    SkyCase(testDescription: "dual-band, faint end", sky: ChannelSky(r: 2.4, g: 1.3, b: 0.9), exposureMs: 120_000, expected: .dualband),
    SkyCase(testDescription: "broadband, blue-dominant", sky: ChannelSky(r: 30, g: 38, b: 42), exposureMs: 120_000, expected: .broadband),
    SkyCase(testDescription: "broadband, green-dominant", sky: ChannelSky(r: 28, g: 40, b: 35), exposureMs: 120_000, expected: .broadband),
    SkyCase(testDescription: "dual-band at 60s normalized", sky: ChannelSky(r: 3, g: 1.8, b: 1.2), exposureMs: 60000, expected: .dualband),
    SkyCase(testDescription: "broadband at 60s normalized", sky: ChannelSky(r: 14, g: 19, b: 21), exposureMs: 60000, expected: .broadband),
    SkyCase(testDescription: "broadband at 300s", sky: ChannelSky(r: 70, g: 95, b: 105), exposureMs: 300_000, expected: .broadband),
    SkyCase(testDescription: "bright but red-dominant", sky: ChannelSky(r: 45, g: 35, b: 30), exposureMs: 120_000, expected: .unknown),
    SkyCase(testDescription: "faint but green-dominant", sky: ChannelSky(r: 2, g: 4, b: 3), exposureMs: 120_000, expected: .unknown),
    SkyCase(testDescription: "amplitude in the gap", sky: ChannelSky(r: 20, g: 12, b: 10), exposureMs: 120_000, expected: .unknown),
    SkyCase(testDescription: "blue is not the floor", sky: ChannelSky(r: 6, g: 2, b: 3), exposureMs: 120_000, expected: .unknown),
    SkyCase(testDescription: "no exposure", sky: ChannelSky(r: 6, g: 3, b: 2), exposureMs: 0, expected: .unknown),
    SkyCase(testDescription: "all zero", sky: ChannelSky(r: 0, g: 0, b: 0), exposureMs: 120_000, expected: .unknown),
    SkyCase(testDescription: "negative sky", sky: ChannelSky(r: -2, g: -3, b: -4), exposureMs: 120_000, expected: .unknown),
  ]

  @Test("both signals must agree, at 1 e-/ADU", arguments: skyCases)
  func testBroadbandVsDualBand(row: SkyCase) {
    #expect(FilterSetClassifier.classify(row.sky, exposureMs: row.exposureMs, eGain: 1) == row.expected)
  }

  @Test("red-dominant means R first and B last; green/blue-dominant is its complement")
  func testChannelSky_dominance() {
    #expect(ChannelSky(r: 6, g: 3, b: 2).isRedDominant)
    #expect(!ChannelSky(r: 6, g: 2, b: 3).isRedDominant)
    #expect(!ChannelSky(r: 3, g: 6, b: 2).isRedDominant)
    #expect(ChannelSky(r: 28, g: 40, b: 35).isGreenBlueDominant)
    #expect(ChannelSky(r: 30, g: 38, b: 42).isGreenBlueDominant)
    #expect(!ChannelSky(r: 45, g: 35, b: 30).isGreenBlueDominant)
  }

  static let egainGain0 = 0.768
  static let egainGain100 = 0.243

  @Test("27 ADU at gain 100 is 6.6 electrons: never broadband (M31-DB)")
  func testBroadbandVsDualBand_highGain() {
    let sky = ChannelSky(r: 23.6, g: 37.2, b: 20.8)
    #expect(FilterSetClassifier.classify(sky, exposureMs: 120_000, eGain: Self.egainGain100) == .unknown)
  }

  @Test("the ADU dead band is dual-band in electrons (IC 1848)")
  func testBroadbandVsDualBand_deadBand() {
    let sky = ChannelSky(r: 25.6, g: 19.4, b: 13.2)
    #expect(FilterSetClassifier.classify(sky, exposureMs: 120_000, eGain: Self.egainGain100) == .dualband)
  }

  @Test(
    "the same sky classifies the same at any analogue gain",
    arguments: [(6.0, true, FilterSet.dualband), (35.0, false, .broadband)])
  func testBroadbandVsDualBand_gainInvariant(electrons: Double, redLeads: Bool, expected: FilterSet) {
    for eGain in [Self.egainGain0, Self.egainGain100] {
      let adu = electrons / eGain
      let sky =
        redLeads
        ? ChannelSky(r: adu * 1.5, g: adu, b: adu * 0.5) : ChannelSky(r: adu * 0.5, g: adu * 1.5, b: adu)
      #expect(FilterSetClassifier.classify(sky, exposureMs: 120_000, eGain: eGain) == expected)
    }
  }

  @Test("no EGAIN, no verdict", arguments: [0.0, -1.0])
  func testBroadbandVsDualBand_noEGain(eGain: Double) {
    for sky in [ChannelSky(r: 6, g: 3, b: 2), ChannelSky(r: 30, g: 38, b: 42)] {
      #expect(FilterSetClassifier.classify(sky, exposureMs: 120_000, eGain: eGain) == .unknown)
    }
  }

  @Test(
    "each Bayer pattern reads its primaries at their own cell positions",
    arguments: [
      ("RGGB", ChannelSky(r: 10, g: 25, b: 40)), ("BGGR", ChannelSky(r: 40, g: 25, b: 10)),
      ("GRBG", ChannelSky(r: 20, g: 25, b: 30)), ("GBRG", ChannelSky(r: 30, g: 25, b: 20)),
    ])
  func testFilterSetClassifier_cfaPatterns(pattern: String, expected: ChannelSky) throws {
    let sky = try #require(
      FilterSetClassifier.cfaSky([10, 20, 10, 20, 30, 40, 30, 40], width: 4, height: 2, pattern: pattern))
    #expect(abs(sky.r - expected.r) < 1e-9)
    #expect(abs(sky.g - expected.g) < 1e-9)
    #expect(abs(sky.b - expected.b) < 1e-9)
  }

  @Test("an unrecognised pattern yields nothing")
  func testFilterSetClassifier_unknownPattern() {
    #expect(FilterSetClassifier.cfaSky([10, 20, 10, 20, 30, 40, 30, 40], width: 4, height: 2, pattern: "XYZW") == nil)
  }

  @Test("the trimmed mean reads the sky, not the stars")
  func testFilterSetClassifier_skyNotStars() throws {
    let image = FilterSetScanTests.starfield(sky: (512, 512, 512), starFraction: 0.05, starADU: 40)
    let sky = try #require(
      FilterSetClassifier.cfaSky(image.planes[0], width: image.width, height: image.height, pattern: "RGGB"))
    #expect(abs(sky.r - 512) <= 0.5)
    #expect(abs(sky.g - 512) <= 0.5)
    #expect(abs(sky.b - 512) <= 0.5)
  }
}
