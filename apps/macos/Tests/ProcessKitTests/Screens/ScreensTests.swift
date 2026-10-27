import Metal
import ProcessKit
import Testing

@Suite(
  "Emission screens: astrocomp's layer chain and tinted screen, from the bundle statistics",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct ScreensTests {
  static let (width, height) = (16, 4)
  static let haStats = ChannelStats(median: 0.05, madn: 0.002, minimum: 0, maximum: 1)

  /// A linear line layer: a ramp from below the background to well above it.
  static func lineRamp() -> [Float] {
    (0..<(width * height)).map { Float($0 % width) / Float(width - 1) * 0.4 + 0.04 }
  }

  static func device() throws -> MTLDevice { try #require(MTLCreateSystemDefaultDevice()) }

  /// Only Hα on, no opening or smoothing: the per-pixel chain alone.
  static func params(_ values: [String: ParamValue] = [:]) throws -> ParamSet {
    var params = ParamSet(schema: EmissionScreensProcess.schema)
    try params.set("oiiiEnabled", .flag(false))
    try params.set("starRadius", .number(0))
    for (id, value) in values { try params.set(id, value) }
    return params
  }

  static func render(
    _ params: ParamSet, base: [Float], layers: [String: [[Float]]],
    layerStats: [String: LayerStats]
  ) throws -> [[Float]] {
    let device = try Self.device()
    let input = try GPUImage(
      device: device, width: width, height: height, planes: [base, base, base])
    let images = try layers.mapValues {
      try GPUImage(device: device, width: width, height: height, planes: $0)
    }
    return try ProcessRunner(device: device).run(
      EmissionScreensProcess(params: params, device: device), input: input,
      stats: LayerStats(channels: []), layers: images, layerStats: layerStats
    ).read()
  }

  /// The formula rows (α, tint, base), shared with `LiveKernelTransitionTests` (card 0136).
  static let formulaRows = [
    (0.95, "red", 0.10), (0.5, "teal", 0.40), (1.0, "gold", 0.0), (0.3, "crimson", 0.9),
    (0.0, "red", 0.5),
  ]

  @Test(
    "the screen equals astrocomp's formula within 1/65535 (α, tint, base)", arguments: formulaRows)
  func testScreenFormula(alpha: Double, tint: String, base: Double) throws {
    let params = try Self.params([
      "haOpacity": .number(alpha), "haTint": .choice(tint), "haBlack": .number(0.115),
    ])
    let stats = ["Ha": LayerStats(channels: [Self.haStats])]
    let line = Self.lineRamp()
    let out = try Self.render(
      params, base: Array(repeating: Float(base), count: line.count), layers: ["Ha": [line]],
      layerStats: stats)
    let stretch = ScreensOracle.mtfParams(median: 0.05, madn: 0.002, target: 0.12, clip: -2.5)
    let settings = ScreensOracle.Line(
      shadows: stretch.shadows, midtone: stretch.midtone, black: 0.115)
    let weights = try #require(ScreenTint(rawValue: tint)).rgb
    for (index, value) in line.enumerated() {
      let prepared = ScreensOracle.prepare(value, settings)
      for channel in 0..<3 {
        let expected = ScreensOracle.screen(
          base: base, value: prepared, alpha: alpha, tint: weights[channel])
        #expect(abs(Double(out[channel][index]) - expected) <= 1.0 / 65535)
      }
    }
  }

  @Test("the OIII boost rolls off above the knee and never reaches 1")
  func testBoostShoulder() throws {
    let params = try Self.params([
      "haEnabled": .flag(false), "oiiiEnabled": .flag(true), "oiiiBoost": .number(1.25),
      "oiiiOpacity": .number(1),
    ])
    let line = Self.lineRamp()
    let out = try Self.render(
      params, base: Array(repeating: 0, count: line.count), layers: ["OIII": [line]],
      layerStats: ["OIII": LayerStats(channels: [Self.haStats])])
    let stretch = ScreensOracle.mtfParams(median: 0.05, madn: 0.002, target: 0.12, clip: -2.5)
    let settings = ScreensOracle.Line(
      shadows: stretch.shadows, midtone: stretch.midtone, boost: 1.25)
    for (index, value) in line.enumerated() {
      let expected = ScreensOracle.prepare(value, settings)
      #expect(abs(Double(out[1][index]) - expected) <= 1.0 / 65535)
      #expect(out[1][index] < 0.98 && out[0][index] == 0)
    }
  }

  @Test("the opening removes a point star from the line layer and keeps a wide region")
  func testOpeningRemovesStars() throws {
    var line = [Float](repeating: 0.05, count: Self.width * Self.height)
    line[1 * Self.width + 3] = 0.6
    for y in 0..<Self.height { for x in 8..<16 { line[y * Self.width + x] = 0.3 } }
    let params = try Self.params(["starRadius": .number(1), "haOpacity": .number(1)])
    let out = try Self.render(
      params, base: Array(repeating: 0, count: line.count), layers: ["Ha": [line]],
      layerStats: ["Ha": LayerStats(channels: [Self.haStats])])
    #expect(out[0][1 * Self.width + 3] == out[0][0], "the star is gone")
    #expect(out[0][2 * Self.width + 12] > 0.5, "the nebula stays")
  }
}
