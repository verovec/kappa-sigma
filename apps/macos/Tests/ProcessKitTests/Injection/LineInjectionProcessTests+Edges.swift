import Metal
import ProcessKit
import Testing

extension LineInjectionProcessTests {
  @Test("a NaN line pixel adds nothing there (fmax), as the oracle says; its neighbours inject")
  func testNaNLinePixelAddsNothing() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    var planes = Self.planes
    planes["Ha"]?[0][5] = .nan
    var layers = try Self.layers(device: device)
    layers["Ha"] = try GPUImage(
      device: device, width: Self.width, height: Self.height, planes: planes["Ha"] ?? [])
    let base = planes["RGB"] ?? []
    let input = try GPUImage(device: device, width: Self.width, height: Self.height, planes: base)
    let out = try ProcessRunner(device: device).run(
      LineInjectionProcess(params: Self.params(["haGain": 2]), device: device), input: input,
      stats: LayerStats(channels: []), layers: layers, layerStats: Self.layerStats
    ).read()
    let lines = try LineInjectionOracle.lines(
      params: Self.params(["haGain": 2]), planes: planes, references: Self.references)
    let expected = LineInjectionOracle.inject(base, lines: lines)
    #expect(out[0][5] == base[0][5])
    #expect(zip(out.joined(), expected.joined()).allSatisfy { abs($0 - $1) <= 1e-6 })
    #expect(out[0][6] != base[0][6])
  }

  @Test("at k = 0 no reference is read: an infinite line pixel injects infinity, not nothing")
  func testInfiniteLinePixelAtZeroK() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    var layers = try Self.layers(device: device)
    var ha = Self.planes["Ha"] ?? []
    ha[0][3] = .infinity
    layers["Ha"] = try GPUImage(device: device, width: Self.width, height: Self.height, planes: ha)
    let input = try GPUImage(
      device: device, width: Self.width, height: Self.height, planes: Self.planes["RGB"] ?? [])
    let out = try ProcessRunner(device: device).run(
      LineInjectionProcess(params: Self.params(["haGain": 1]), device: device), input: input,
      stats: LayerStats(channels: []), layers: layers, layerStats: Self.layerStats
    ).read()
    #expect(out[0][3] == .infinity)
  }

  @Test("where a line adds nothing the base keeps its bits, −0.0 included")
  func testNoExcessKeepsBits() throws {
    var base = Self.planes["RGB"] ?? []
    let ha = Self.planes["Ha"]?[0] ?? []
    let index = try #require(ha.indices.first { ha[$0] < 0.15 })
    base[0][index] = -0.0
    let out = try Self.render(["haGain": 1, "haBlack": 0.15], base: base)
    #expect(out[0][index].bitPattern == (-0.0 as Float).bitPattern)
  }

  @Test("the black point is offered at the line's sky: its median, less k × the reference's")
  func testBlackSuggestion() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let reason = try #require(LineInjectionProcess.suggestionReasons.last)
    var layers = Self.layerStats
    layers["RGB"] = LayerStats(
      channels: [0.04, 0.03, 0.02].map {
        ChannelStats(median: $0, madn: 0.001, minimum: 0, maximum: 1)
      })
    let plain = try LineInjectionProcess(
      params: Self.params(["haGain": 1, "siiGain": 1]), device: device)
    let black = plain.suggestions(stats: LayerStats(channels: []), layers: layers)
      .filter { $0.paramID.hasSuffix("Black") }
    #expect(
      black == [
        Suggestion(paramID: "haBlack", value: .number(0.05), reason: reason),
        Suggestion(paramID: "siiBlack", value: .number(0.03), reason: reason),
      ])
    let subtracted = try LineInjectionProcess(
      params: Self.params(["haGain": 1, "haContinuumK": 0.5]), device: device)
    let derived = subtracted.suggestions(stats: LayerStats(channels: []), layers: layers)
      .first { $0.paramID == "haBlack" }
    guard case .number(let value)? = derived?.value else {
      Issue.record("no black point offered with k > 0")
      return
    }
    #expect(abs(value - (0.05 - 0.5 * 0.04)) <= 1e-12)
    #expect(subtracted.params.number("haBlack") == 0, "offered, never applied")
  }
}

extension LineInjectionProcessTests {
  @Test(
    "only the injecting lines are bound, in canonical order from slot 0; the result is the oracle",
    arguments: [
      (["siiGain": 2.0], ["SII"]),
      (["haGain": 1, "siiGain": 2, "oiiiBlack": 0.1, "oiiiContinuumK": 0.3], ["Ha", "SII"]),
      (["siiGain": 1, "oiiiGain": 1, "haGain": 1, "haRed": 0], ["OIII", "SII"]),
    ] as [([String: Double], [String])])
  func testSlotCompactionKeepsOrder(values: [String: Double], slots: [String]) throws {
    let params = try Self.params(values)
    #expect(LineInjectionProcess.boundLines(params).map(\.layerID) == slots)
    let base = Self.planes["RGB"] ?? []
    let lines = try LineInjectionOracle.lines(
      params: params, planes: Self.planes, references: Self.references)
    let expected = LineInjectionOracle.inject(base, lines: lines)
    let out = try Self.render(values)
    #expect(zip(out.joined(), expected.joined()).allSatisfy { abs($0 - $1) <= 1e-6 })
    #expect(out != base)
  }
}
