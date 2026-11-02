import ProcessKit
import Testing

/// Card 0164: an « Other line » slot screens a custom line layer exactly as a catalogued line's
/// card does with the same values, and changes nothing until it is switched on.
extension ScreensTests {
  /// Hα's own values, copied onto slot 1 bound to `Filter5`, Hα off.
  static func slotParams(_ values: [String: ParamValue] = [:]) throws -> ParamSet {
    var params = try Self.params(["haEnabled": .flag(false)])
    let copied = ["Background", "Black", "Opacity", "Tint", "Boost"]
    let catalogued = try Self.params()
    for name in copied { try params.set("custom1" + name, try #require(catalogued["ha" + name])) }
    try params.set("custom1Layer", .choice("Filter5"))
    try params.set("custom1Enabled", .flag(true))
    for (id, value) in values { try params.set(id, value) }
    return params
  }

  static let haOnly: [String: LayerStats] = ["Ha": LayerStats(channels: [haStats])]
  static let filter5Only: [String: LayerStats] = ["Filter5": LayerStats(channels: [haStats])]

  @Test(
    "a slot screens its layer bit for bit like Hα's card with the same values",
    arguments: [[:], ["custom1Black": .number(0.05), "custom1Boost": .number(2)]]
      as [[String: ParamValue]])
  func testCustomSlot_Screens(values: [String: ParamValue]) throws {
    let base = Self.lineRamp().map { $0 * 0.5 }
    var catalogued = try Self.params()
    for (id, value) in values {
      try catalogued.set(id.replacingOccurrences(of: "custom1", with: "ha"), value)
    }
    let expected = try Self.render(
      catalogued, base: base, layers: ["Ha": [Self.lineRamp()]], layerStats: Self.haOnly)
    let out = try Self.render(
      try Self.slotParams(values), base: base, layers: ["Filter5": [Self.lineRamp()]],
      layerStats: Self.filter5Only)
    #expect(out == expected)
    #expect(out != [base, base, base], "the slot screens something")
  }

  @Test("a bound slot left off changes no bit")
  func testCustomSlot_ScreensDefaultsAreIdentity() throws {
    let base = Self.lineRamp().map { $0 * 0.5 }
    let layers = ["Ha": [Self.lineRamp()], "Filter5": [Self.lineRamp()]]
    let stats = Self.haOnly.merging(Self.filter5Only) { $1 }
    var bound = try Self.params()
    try bound.set("custom1Layer", .choice("Filter5"))
    let out = try Self.render(bound, base: base, layers: layers, layerStats: stats)
    #expect(out == (try Self.render(Self.params(), base: base, layers: layers, layerStats: stats)))
  }

  @Test("a slot has no continuum rows, lists custom line layers, and reads its layer once on")
  func testCustomSlot_ScreensSchema() throws {
    #expect(EmissionScreensProcess.schema.spec("custom1Continuum") == nil)
    #expect(EmissionScreensProcess.schema.spec("custom4Enabled") != nil)
    let spec = try #require(EmissionScreensProcess.schema.spec("custom2Layer"))
    #expect(
      EmissionScreensProcess.layerOptions(for: spec, planes: ["RGB": 3, "Ha": 1, "Filter5": 1])
        == ["none", "Filter5"])
    let params = try Self.slotParams()
    #expect(EmissionScreensProcess.layersRead(params, layerIDs: ["RGB", "Filter5"]) == ["Filter5"])
    #expect(
      EmissionScreensProcess.hiddenParameters(params, layerIDs: ["RGB", "Filter5"])
        .isDisjoint(with: ["custom1Layer", "custom1Enabled", "custom1Tint"]))
  }
}
