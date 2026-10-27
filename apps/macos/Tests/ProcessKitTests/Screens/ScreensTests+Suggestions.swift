import FilterKit
import Metal
import ProcessKit
import StackKit
import Testing

extension ScreensTests {
  static func process(_ values: [String: ParamValue]) throws -> EmissionScreensProcess {
    try EmissionScreensProcess(params: Self.params(values), device: Self.device())
  }

  static func stats(median: Double, madn: Double) -> LayerStats {
    LayerStats(channels: [ChannelStats(median: median, madn: madn, minimum: 0, maximum: 1)])
  }

  @Test("linked layers share the first curve, but each line's σ is its own noise")
  func testLinkedSigmaUsesOwnNoise() throws {
    let process = try Self.process([
      "oiiiEnabled": .flag(true), "linkLayers": .flag(true), "oiiiBlack": .number(0.1),
    ])
    let layers = [
      "Ha": Self.stats(median: 0.05, madn: 0.002), "OIII": Self.stats(median: 0.05, madn: 0.01),
    ]
    let ha = try process.lineStretch(try #require(EmissionLine(.hydrogenAlpha)), layerStats: layers)
    let oiii = try process.lineStretch(try #require(EmissionLine(.oxygenIII)), layerStats: layers)
    #expect(oiii.shadows == ha.shadows && oiii.midtone == ha.midtone)
    #expect(abs(oiii.stretchedNoise / ha.stretchedNoise - 5) <= 1e-9)
    #expect(
      abs(
        try process.blackInSigma(try #require(EmissionLine(.oxygenIII)), layerStats: layers) - 0.1
          / oiii.stretchedNoise)
        <= 1e-12)
  }

  @Test("one line that cannot be stretched costs only its own suggestions")
  func testSuggestionsPerLine() throws {
    let process = try Self.process(["oiiiEnabled": .flag(true), "oiiiContinuum": .flag(true)])
    let layers = [
      "Ha": Self.stats(median: 0.05, madn: 0.002), "OIII": Self.stats(median: 0.05, madn: 0.01),
    ]
    let ids = process.suggestions(stats: LayerStats(channels: []), layers: layers).map(\.paramID)
    #expect(ids == ["haBlack"])
  }

  @Test(
    "the bundle k is suggested inside the schema's range, and only with its reference plane",
    arguments: [(0.7, "RGB.r", 0.7), (6.2, "RGB.r", 5.0), (0.7, nil, nil)]
      as [(Double, String?, Double?)])
  func testContinuumSuggestion(k: Double, reference: String?, expected: Double?) throws {
    let process = try Self.process([:])
    let layers = [
      "Ha": LayerStats(
        channels: [ChannelStats(median: 0.05, madn: 0.002, minimum: 0, maximum: 1)],
        continuumK: k, continuumReference: reference)
    ]
    let suggested = process.suggestions(stats: LayerStats(channels: []), layers: layers)
      .first { $0.paramID == "haContinuumK" }
    #expect(suggested?.value == expected.map(ParamValue.number))
  }

  @Test("a k that subtracts the whole background is refused with the reason")
  func testContinuumKTooHigh() throws {
    let process = try Self.process(["haContinuum": .flag(true), "haContinuumK": .number(0.7)])
    var layers = Self.continuumStats()
    layers["Ha"] = LayerStats(
      channels: [ChannelStats(median: 0.05, madn: 0.002, minimum: 0, maximum: 1)],
      continuumK: 0.7, continuumReference: "RGB.r")
    #expect {
      try process.lineStretch(try #require(EmissionLine(.hydrogenAlpha)), layerStats: layers)
    } throws: { "\($0)".contains("subtracts the whole background") }
  }
}
