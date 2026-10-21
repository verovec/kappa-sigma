import Metal
import ProcessKit
import Testing

/// `SaturationProcess`: the shader against `ColourOracle` (astrocomp's HSL block, the legacy
/// luminosity LUTs and the `desat` tool).
@Suite(
  "Saturation: masked HSL boost, star-core desaturation, luma desaturation",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct SaturationTests {
  struct Case: CustomTestStringConvertible, Sendable {
    let amount: Double
    let masked: Bool
    let starDesat: Double
    var testDescription: String { "sat \(amount) masked \(masked) star desat \(starDesat)" }
  }

  @Test(
    "the masked band equals the saturationMaskLUT formulation within 1/65535",
    arguments: [
      Case(amount: 0.32, masked: true, starDesat: 0),
      Case(amount: 0.30, masked: false, starDesat: 0),
      Case(amount: 1.5, masked: true, starDesat: 0),
      Case(amount: 0.32, masked: true, starDesat: 0.25),
      Case(amount: 0, masked: true, starDesat: 1),
    ])
  func testMaskedBandMatchesLUT(_ example: Case) throws {
    let field = ColourFixtures.field()
    let out = try ColourFixtures.run(
      SaturationProcess.self,
      [
        "amount": .number(example.amount), "masked": .flag(example.masked),
        "starDesat": .number(example.starDesat),
      ], planes: field)
    let expected = ColourFixtures.map(field) {
      ColourOracle.saturate(
        $0, amount: Float(example.amount), masked: example.masked,
        starDesat: Float(example.starDesat), lumaK: 1)
    }
    #expect(ColourFixtures.maxDifference(out, expected) <= 1.0 / 65535)
  }

  @Test("amount 0, no star desaturation and k = 1 is the identity, bit for bit")
  func testDefaultsAreIdentity() throws {
    let field = ColourFixtures.field()
    #expect(try ColourFixtures.run(SaturationProcess.self, [:], planes: field) == field)
  }

  @Test("the mask follows the band the panel shows (lo/hi/roll-off/floor)")
  func testBandParameters() throws {
    let field = ColourFixtures.field()
    let out = try ColourFixtures.run(
      SaturationProcess.self,
      [
        "amount": .number(0.5), "bandLow": .number(0.2), "bandHigh": .number(0.3),
        "rolloffStart": .number(0.8), "highlightFloor": .number(0.6),
      ], planes: field)
    let expected = ColourFixtures.map(field) { rgb in
      ColourOracle.saturate(rgb, amount: 0.5, masked: true, starDesat: 0, lumaK: 1) { light in
        ColourOracle.saturationMask(light, low: 0.2, high: 0.3, rolloff: 0.8, floor: 0.6)
      }
    }
    #expect(ColourFixtures.maxDifference(out, expected) <= 1.0 / 65535)
  }

  @Test("luma desaturation: k = 1 is the identity, k = 0 is grey at the Rec. 709 luma")
  func testLumaDesatK() throws {
    let field = ColourFixtures.field()
    #expect(
      try ColourFixtures.run(SaturationProcess.self, ["lumaDesat": .number(1)], planes: field)
        == field)
    let grey = try ColourFixtures.run(
      SaturationProcess.self, ["lumaDesat": .number(0)], planes: field)
    for index in field[0].indices {
      let rgb = ColourFixtures.pixel(field, index)
      let luma = 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]
      #expect(ColourFixtures.pixel(grey, index).allSatisfy { abs($0 - luma) <= 1e-6 })
    }
    let soft = try ColourFixtures.run(
      SaturationProcess.self, ["lumaDesat": .number(0.62)], planes: field)
    let expected = ColourFixtures.map(field) {
      ColourOracle.saturate($0, amount: 0, masked: true, starDesat: 0, lumaK: 0.62)
    }
    #expect(ColourFixtures.maxDifference(soft, expected) <= 1.0 / 65535)
  }

  @Test("a band whose edges cross is refused with the reason, never reordered")
  func testCrossedBandRefused() throws {
    #expect(throws: ProcessError.self) {
      try ColourFixtures.run(
        SaturationProcess.self,
        ["amount": .number(0.3), "bandLow": .number(0.5), "bandHigh": .number(0.4)],
        planes: ColourFixtures.field())
    }
  }

  @Test("a mono image passes through untouched")
  func testMonoIsIdentity() throws {
    let plane = [ColourFixtures.field()[0]]
    #expect(
      try ColourFixtures.run(SaturationProcess.self, ["amount": .number(0.5)], planes: plane)
        == plane)
  }

  @Test("PO's IC 1848 \"doux\" and M31 values are offered as suggestions, never applied")
  func testSuggestions() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let process = try SaturationProcess(
      params: ParamSet(schema: SaturationProcess.schema), device: device)
    let suggestions = process.suggestions(stats: LayerStats(channels: []))
    #expect(suggestions.map(\.paramID) == ["amount", "masked", "lumaDesat"])
    #expect(suggestions.map(\.reason).allSatisfy(SaturationProcess.suggestionReasons.contains))
    #expect(process.params.number("amount") == 0)
  }
}
