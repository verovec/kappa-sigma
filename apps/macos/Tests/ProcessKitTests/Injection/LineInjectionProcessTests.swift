import Metal
import ProcessKit
import Testing

@Suite(
  "Line injection: gain · share · max(line − k·ref − black, 0) added to the linear RGB base",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct LineInjectionProcessTests {
  static let width = 16
  static let height = 8

  /// One oracle row: the panel values, and whether a half mask restricts the result.
  struct Case: CustomTestStringConvertible, Sendable {
    let name: String
    let values: [String: Double]
    var masked = false
    var testDescription: String { name }
  }

  /// Deterministic values in `range`, different per `seed`.
  static func plane(seed: UInt64, in range: ClosedRange<Float>) -> [Float] {
    var state = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    return (0..<(width * height)).map { _ in
      state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      let unit = Float(state >> 40) / Float(1 << 24)
      return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
  }

  /// The bundle: an RGB base near the sky with a few bright pixels, and three line layers whose
  /// excess over k·ref − black is sometimes negative (the clamp shows).
  static let planes: [String: [[Float]]] = [
    "RGB": (0..<3).map { plane(seed: 11 + UInt64($0), in: 0.02...0.95) },
    "Ha": [plane(seed: 21, in: 0...0.4)],
    "OIII": [plane(seed: 22, in: 0...0.3)],
    "SII": [plane(seed: 23, in: 0...0.2)],
  ]

  /// The continuum reference the bundle fitted each line against.
  static let references = ["Ha": "RGB.r", "OIII": "RGB.g"]

  static let layerStats: [String: LayerStats] = [
    "Ha": LayerStats(
      channels: [ChannelStats(median: 0.05, madn: 0.002, minimum: 0, maximum: 0.4)],
      continuumK: 0.6, continuumReference: "RGB.r"),
    "OIII": LayerStats(
      channels: [ChannelStats(median: 0.04, madn: 0.002, minimum: 0, maximum: 0.3)],
      continuumK: 7.5, continuumReference: "RGB.g"),
    "SII": LayerStats(
      channels: [ChannelStats(median: 0.03, madn: 0.002, minimum: 0, maximum: 0.2)],
      continuumK: 0.4),
  ]

  static let halfMask: [Float] = (0..<(width * height)).map { Float($0 % width) / Float(width) }

  static func params(_ values: [String: Double]) throws -> ParamSet {
    var params = ParamSet(schema: LineInjectionProcess.schema)
    for (id, value) in values { try params.set(id, .number(value)) }
    return params
  }

  static func layers(device: MTLDevice, ids: [String] = ["RGB", "Ha", "OIII", "SII"]) throws
    -> [String: GPUImage]
  {
    var layers: [String: GPUImage] = [:]
    for id in ids {
      layers[id] = try GPUImage(
        device: device, width: width, height: height, planes: planes[id] ?? [])
    }
    return layers
  }

  static func render(
    _ values: [String: Double], base: [[Float]] = planes["RGB"] ?? [], masked: Bool = false,
    ids: [String] = ["RGB", "Ha", "OIII", "SII"], stats: [String: LayerStats] = layerStats
  ) throws -> [[Float]] {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let input = try GPUImage(device: device, width: width, height: height, planes: base)
    let mask =
      try masked
      ? GPUImage(device: device, width: width, height: height, planes: [halfMask]) : nil
    return try ProcessRunner(device: device).run(
      LineInjectionProcess(params: params(values), device: device), input: input,
      stats: LayerStats(channels: []), layers: layers(device: device, ids: ids),
      layerStats: stats, mask: mask
    ).read()
  }

  @Test("zero gains return the head bit for bit, whatever k, black and the shares say")
  func testZeroGainsIsIdentity() throws {
    var base = Self.planes["RGB"] ?? []
    base[0][0] = -0.0
    base[1][1] = 3.5
    let out = try Self.render(
      [
        "haContinuumK": 2, "haBlack": 0.1, "oiiiRed": 1, "oiiiContinuumK": 0.5, "siiBlack": 0.3,
      ], base: base)
    #expect(out.map { $0.map(\.bitPattern) } == base.map { $0.map(\.bitPattern) })
    for spec in LineInjectionProcess.schema.specs where spec.id.hasSuffix("Gain") {
      #expect(spec.defaultValue == .number(0), "\(spec.id)")
    }
  }

  @Test(
    "the kernel equals the CPU oracle (max |Δ| ≤ 1e-6)",
    arguments: [
      Case(name: "Hα only", values: ["haGain": 1.5]),
      Case(name: "OIII split", values: ["oiiiGain": 2, "oiiiGreen": 0.7, "oiiiBlue": 0.3]),
      Case(
        name: "k > 0",
        values: [
          "haGain": 1, "haContinuumK": 0.8, "oiiiGain": 1,
          "oiiiContinuumK": 1.2,
        ]),
      Case(name: "black", values: ["haGain": 1, "haBlack": 0.15, "siiGain": 3, "siiBlack": 0.05]),
      Case(name: "mask", values: ["haGain": 2, "oiiiGain": 4, "oiiiRed": 0.2], masked: true),
    ])
  func testMatchesCPUOracle(row: Case) throws {
    let params = try Self.params(row.values)
    let base = Self.planes["RGB"] ?? []
    let lines = try LineInjectionOracle.lines(
      params: params, planes: Self.planes, references: Self.references)
    var expected = LineInjectionOracle.inject(base, lines: lines)
    if row.masked {
      expected = LineInjectionOracle.blend(input: base, processed: expected, mask: Self.halfMask)
    }
    let out = try Self.render(row.values, masked: row.masked)
    let deltas = zip(out.joined(), expected.joined()).map { abs(Double($0) - Double($1)) }
    #expect(deltas.count == 3 * Self.width * Self.height)
    #expect(deltas.max() ?? .infinity <= 1e-6)
    #expect(out != base, "the case injects something")
  }

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

  @Test("no normalisation, no clip: a bright base plus a line goes above 1 and stays there")
  func testValuesAboveOneStay() throws {
    let base = (0..<3).map { _ in [Float](repeating: 0.9, count: Self.width * Self.height) }
    let out = try Self.render(["haGain": 4], base: base)
    let line = Self.planes["Ha"]?[0] ?? []
    #expect(out[0].max() ?? 0 > 1)
    #expect(zip(out[0], line).allSatisfy { abs($0 - (0.9 + 4 * $1)) <= 1e-6 })
    #expect(out[1] == base[1] && out[2] == base[2], "Hα goes into red only by default")
  }

  @Test("the bundle k is only a suggestion, with its reference plane; every default k stays 0")
  func testContinuumKIsSuggestionOnly() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let idle = try LineInjectionProcess(params: Self.params([:]), device: device)
    #expect(
      idle.suggestions(stats: LayerStats(channels: []), layers: Self.layerStats).isEmpty,
      "no gain, no k offered: as the screens offer k only for an enabled line")
    let process = try LineInjectionProcess(
      params: Self.params(["haGain": 1, "oiiiGain": 1, "siiGain": 1]), device: device)
    let suggestions = process.suggestions(
      stats: LayerStats(channels: []), layers: Self.layerStats)
    #expect(
      suggestions == [
        Suggestion(
          paramID: "haContinuumK", value: .number(0.6),
          reason: "the continuum scale fitted on the stack against the colour base's red plane"),
        Suggestion(
          paramID: "oiiiContinuumK", value: .number(5),
          reason: "the continuum scale fitted on the stack against the colour base's green plane"),
      ], "OIII's 7.5 offered at the bound, as the screens do; SII has no reference plane: none")
    #expect(suggestions.allSatisfy { LineInjectionProcess.suggestionReasons.contains($0.reason) })
    for prefix in LineInjectionOracle.prefixes {
      #expect(process.params.number(prefix + "ContinuumK") == 0)
    }
  }

  @Test(
    "each reference plane has its own reason",
    arguments: [
      ("R", "the continuum scale fitted on the stack against the R layer"),
      ("L", "the continuum scale fitted on the stack against the L layer"),
      ("OSC.g", "the continuum scale fitted on the stack against the colour base's green plane"),
      ("RGB.b", "the continuum scale fitted on the stack against the colour base's blue plane"),
      ("X", "the continuum scale fitted on the stack"),
    ])
  func testReasonPerReference(token: String, reason: String) {
    #expect(LineInjectionProcess.continuumReason(reference: token) == reason)
  }

  @Test("k > 0 without a fitted reference, or a gain without its layer, is refused by name")
  func testRefusals() throws {
    #expect(
      throws: ProcessError.invalidParameter(
        "[SII]: the bundle has no continuum fit: set k to 0")
    ) {
      try Self.render(["siiGain": 1, "siiContinuumK": 0.4])
    }
    #expect(throws: ProcessError.missingLayer("OIII")) {
      try Self.render(["oiiiGain": 1], ids: ["RGB", "Ha"])
    }
    #expect(try Self.render(["haGain": 1], ids: ["RGB", "Ha"]) != Self.planes["RGB"])
  }

  @Test("passes every contract with the bundle layers (and under the half mask)")
  func testContracts() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let input = try GPUImage(
      device: device, width: Self.width, height: Self.height, planes: Self.planes["RGB"] ?? [])
    let contracts = try ProcessContracts(
      device: device, input: input, stats: LayerStats(channels: []),
      layers: Self.layers(device: device), layerStats: Self.layerStats)
    let params = try Self.params([
      "haGain": 1.2, "haContinuumK": 0.5, "oiiiGain": 2, "oiiiBlack": 0.02,
    ])
    #expect(try contracts.violations(of: LineInjectionProcess.self, params: params).isEmpty)
  }

  @Test("a linear process needing colour and emission layers, right after the combination")
  func testRegistered() throws {
    let ids = try ProcessRegistry.standard().ids
    let index = try #require(ids.firstIndex(of: LineInjectionProcess.id))
    #expect(ids[index - 1] == ChannelCombinationProcess.id)
    #expect(LineInjectionProcess.stage == .linear)
    #expect(LineInjectionProcess.requires == [.color, .emission])
  }
}
