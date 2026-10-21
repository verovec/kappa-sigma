import Metal
import ProcessKit
import RenderKit
import Testing

/// `ColourBalanceProcess`: background neutralisation from a measured region and RGB gains, both
/// as values the panel shows — the region only fills suggestions (R2).
@Suite(
  "Colour balance: neutralise a sky region, RGB gains",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct ColourBalanceTests {
  /// A linear sky with a per-channel pedestal and noise, and a bright object on the right half.
  static func sky(pedestals: [Float]) -> [[Float]] {
    var seed: UInt32 = 77
    return pedestals.map { pedestal in
      (0..<ColourFixtures.width * ColourFixtures.height).map { index in
        seed = seed &* 1_664_525 &+ 1_013_904_223
        let noise = Float(seed >> 8) / Float(1 << 24) * 0.004
        return pedestal + noise + (index % ColourFixtures.width >= 40 ? 0.3 : 0)
      }
    }
  }

  static let skyRegion = PixelRegion(x: 2, y: 2, width: 30, height: 12)

  static func measure(_ planes: [[Float]]) throws -> [Double] {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let image = try GPUImage(
      device: device, width: ColourFixtures.width, height: ColourFixtures.height, planes: planes)
    return try ColourBalanceProcess.regionMedians(image, region: skyRegion)
  }

  static func spread(_ values: [Double]) -> Double {
    (values.max() ?? 0) - (values.min() ?? 0)
  }

  static func applying(_ suggestions: [Suggestion], to values: [String: ParamValue] = [:])
    -> [String: ParamValue]
  {
    suggestions.reduce(into: values) { $0[$1.paramID] = $1.value }
  }

  @Test(
    "neutralising a region makes its per-channel medians equal within 1e-5",
    arguments: [[0.10, 0.08, 0.12], [0.02, 0.05, 0.03], [0.2, 0.2, 0.2]] as [[Float]])
  func testNeutraliseRegionAndGains(pedestals: [Float]) throws {
    let field = Self.sky(pedestals: pedestals)
    let medians = try Self.measure(field)
    let offsets = ColourBalanceProcess.neutraliseSuggestions(regionMedians: medians)
    #expect(offsets.map(\.paramID) == ["offsetRed", "offsetGreen", "offsetBlue"])
    let neutral = try ColourFixtures.run(
      ColourBalanceProcess.self, Self.applying(offsets), planes: field)
    let after = try Self.measure(neutral)
    #expect(Self.spread(after) <= 1e-5, "\(after)")
    let (level, before): (Double, Double) = (after.reduce(0, +) / 3, medians.reduce(0, +) / 3)
    #expect(abs(level - before) <= 1e-5, "the level is kept")

    let gains = ColourBalanceProcess.greySuggestions(
      regionMedians: medians, params: ParamSet(schema: ColourBalanceProcess.schema))
    #expect(gains.map(\.paramID) == ["gainRed", "gainGreen", "gainBlue"])
    let grey = try Self.measure(
      try ColourFixtures.run(ColourBalanceProcess.self, Self.applying(gains), planes: field))
    #expect(Self.spread(grey) <= 1e-5, "\(grey)")
  }

  @Test(
    "gains scale each channel exactly, and the gains shown are the gains applied",
    arguments: [[1.0, 1.0, 1.0], [1.2, 0.9, 1.5], [0.5, 2.0, 1.0]])
  func testGains(gains: [Double]) throws {
    let field = Self.sky(pedestals: [0.1, 0.1, 0.1])
    let out = try ColourFixtures.run(
      ColourBalanceProcess.self,
      [
        "gainRed": .number(gains[0]), "gainGreen": .number(gains[1]), "gainBlue": .number(gains[2]),
      ], planes: field)
    for plane in 0..<3 {
      let gain = Float(gains[plane])
      let expected: [Float] = field[plane].map { ($0 + 0) * gain }
      #expect(out[plane] == expected)
    }
  }

  @Test("gains 1 and no offset are the identity, bit for bit (−0.0 kept); mono passes through")
  func testIdentity() throws {
    var field = Self.sky(pedestals: [0.1, 0.05, 0.2])
    field[0][0] = -0.0
    let out = try ColourFixtures.run(ColourBalanceProcess.self, [:], planes: field)
    #expect(out.map { $0.map(\.bitPattern) } == field.map { $0.map(\.bitPattern) })
    let mono = [field[0]]
    #expect(
      try ColourFixtures.run(ColourBalanceProcess.self, ["gainRed": .number(2)], planes: mono)
        == mono)
  }

  @Test("a grey gain the parameter cannot hold is not offered (it would be clamped)")
  func testGreyOutOfBounds() {
    let params = ParamSet(schema: ColourBalanceProcess.schema)
    #expect(
      ColourBalanceProcess.greySuggestions(regionMedians: [0.05, 0.05, 0.004], params: params)
        .isEmpty)
    #expect(
      ColourBalanceProcess.greySuggestions(regionMedians: [0.05, 0.05, 0.01], params: params)
        .count == 3)
  }

  @Test("a region outside the image, or empty, is refused with the reason")
  func testRegionOutsideRefused() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let image = try GPUImage(
      device: device, width: 8, height: 8,
      planes: Array(repeating: [Float](repeating: 0, count: 64), count: 3))
    for region in [
      PixelRegion(x: 4, y: 4, width: 8, height: 2), PixelRegion(x: 0, y: 0, width: 0, height: 4),
    ] {
      #expect(throws: ProcessError.self) {
        try ColourBalanceProcess.regionMedians(image, region: region)
      }
    }
  }
}
