import Foundation
import Metal
import ProcessKit
import Testing

extension ScreensTests {
  /// Hα = 0.5 · R + emission, except a band where Hα/R is 0.9: an estimator fitting k on this
  /// image would not find 0.5. The bundle says 0.7, so neither 0.5 nor the image decides.
  static func continuumFixture() -> (ha: [Float], red: [Float]) {
    let red = (0..<(width * height)).map { Float($0 % width) / Float(width) * 0.5 + 0.1 }
    let ha = red.enumerated().map { index, value in
      index / width == 0 ? value * 0.9 : value * 0.5 + (index % 5 == 0 ? 0.2 : 0)
    }
    return (ha, red)
  }

  static func continuumStats(k: Double = 0.7) -> [String: LayerStats] {
    [
      "Ha": LayerStats(
        channels: [ChannelStats(median: 0.2, madn: 0.01, minimum: 0, maximum: 1)], continuumK: k,
        continuumReference: "RGB.r"),
      "RGB": LayerStats(
        channels: Array(
          repeating: ChannelStats(median: 0.3, madn: 0.01, minimum: 0, maximum: 1), count: 3)),
    ]
  }

  @Test("continuum subtraction applies the k shown, never one estimated from the image")
  func testContinuumSubUsesBundleK() throws {
    let (ha, red) = Self.continuumFixture()
    let layers = ["Ha": [ha], "RGB": [red, red, red]]
    let stats = Self.continuumStats()
    func render(k: Double) throws -> [[Float]] {
      let params = try Self.params([
        "haContinuum": .flag(true), "haContinuumK": .number(k), "haOpacity": .number(1),
      ])
      return try Self.render(
        params, base: Array(repeating: 0, count: ha.count), layers: layers, layerStats: stats)
    }
    let (half, third) = (try render(k: 0.5), try render(k: 0.3))
    #expect(half[0] != third[0], "changing k changes the layer")
    // Derived stats: median 0.2 − 0.5·0.3, MADN √(0.01² + 0.5²·0.01²).
    let stretch = ScreensOracle.mtfParams(
      median: 0.2 - 0.5 * 0.3, madn: (0.0001 + 0.25 * 0.0001).squareRoot(), target: 0.12,
      clip: -2.5)
    let line = ScreensOracle.Line(shadows: stretch.shadows, midtone: stretch.midtone, k: 0.5)
    for index in ha.indices {
      let expected = ScreensOracle.prepare(ha[index], reference: red[index], line)
      #expect(abs(Double(half[0][index]) - expected) <= 1.0 / 65535)
    }
    let process = try EmissionScreensProcess(
      params: Self.params(["haContinuum": .flag(true)]), device: Self.device())
    let suggested = process.suggestions(stats: LayerStats(channels: []), layers: stats)
    #expect(suggested.contains { $0.paramID == "haContinuumK" && $0.value == .number(0.7) })
  }

  @Test("no continuum fit in the bundle: the subtraction is refused with the reason")
  func testContinuumWithoutFit() throws {
    let (ha, red) = Self.continuumFixture()
    let params = try Self.params(["haContinuum": .flag(true), "haContinuumK": .number(0.5)])
    var stats = Self.continuumStats()
    stats["Ha"] = LayerStats(channels: stats["Ha"]?.channels ?? [])
    #expect {
      try Self.render(
        params, base: Array(repeating: 0, count: ha.count),
        layers: ["Ha": [ha], "RGB": [red, red, red]], layerStats: stats)
    } throws: { "\($0)".contains("no continuum fit") }
  }

  @Test(
    "the black point reads in σ of the stretched bundle noise, not of the image",
    arguments: [(0.05, 0.002, 0.115), (0.0529, 0.000132, 0.115), (0.1, 0.01, 0.3)])
  func testSigmaLabel(median: Double, madn: Double, black: Double) throws {
    let process = try EmissionScreensProcess(
      params: Self.params(["haBlack": .number(black)]), device: Self.device())
    let stats = [
      "Ha": LayerStats(channels: [
        ChannelStats(median: median, madn: madn, minimum: 0, maximum: 1)
      ])
    ]
    // The noise through the curve: a central difference of the stretch at the median.
    let (c, m) = ScreensOracle.mtfParams(median: median, madn: madn, target: 0.12, clip: -2.5)
    let curve = { (v: Double) in ScreensOracle.mtf((v - c) / (1 - c), m) }
    let step = madn * 1e-3
    let slope = (curve(median + step) - curve(median - step)) / (2 * step)
    let sigma = try process.blackInSigma(.hydrogenAlpha, layerStats: stats)
    #expect(abs(sigma - black / (slope * madn)) <= 1e-4 * sigma)
    let suggested = process.suggestions(stats: LayerStats(channels: []), layers: stats)
    let blackSuggestion = try #require(suggested.first { $0.paramID == "haBlack" })
    guard case .number(let value) = blackSuggestion.value else {
      Issue.record("the black point suggestion is not a number")
      return
    }
    #expect(abs(value - min(3 * slope * madn, 0.9)) <= 1e-4 * value)
  }

  @Test("an enabled line without its layer is greyed with the reason and refused")
  func testMissingLayer() throws {
    let params = try Self.params(["oiiiEnabled": .flag(true)])
    #expect(
      EmissionScreensProcess.unavailableReason(params: params, present: ["RGB", "Ha"])
        == "[OIII] screen needs the OIII layer")
    #expect(
      EmissionScreensProcess.unavailableReason(params: params, present: ["Ha", "OIII"]) == nil)
    #expect(throws: ProcessError.missingLayer("OIII")) {
      try Self.render(
        params, base: Array(repeating: 0, count: Self.width * Self.height),
        layers: ["Ha": [Self.lineRamp()]],
        layerStats: [
          "Ha": LayerStats(channels: [Self.haStats]), "OIII": LayerStats(channels: [Self.haStats]),
        ])
    }
  }

  @Test("passes every contract with its layers, the opening and smoothing on, under a mask")
  func testContracts() throws {
    let device = try Self.device()
    let (ha, red) = Self.continuumFixture()
    let layers = try ["Ha": [ha], "OIII": [red], "RGB": [red, red, red]].mapValues {
      try GPUImage(device: device, width: Self.width, height: Self.height, planes: $0)
    }
    var stats = Self.continuumStats()
    stats["OIII"] = LayerStats(channels: [Self.haStats])
    let input = try GPUImage(
      device: device, width: Self.width, height: Self.height, planes: [red, ha, red])
    let contracts = try ProcessContracts(
      device: device, input: input, stats: LayerStats(channels: []), layers: layers,
      layerStats: stats)
    let params = try Self.params([
      "oiiiEnabled": .flag(true), "starRadius": .number(2), "smooth": .number(1),
      "haContinuum": .flag(true), "haContinuumK": .number(0.5),
    ])
    #expect(try contracts.violations(of: EmissionScreensProcess.self, params: params).isEmpty)
  }
}
