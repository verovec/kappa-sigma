import ImageKit
import ProcessKit
import Testing

/// Card 0140: no camera chosen for the user — SPCC waits for its sensor and filters, the route
/// (OSC or mono) follows the bundle's layers, the header's camera is only a suggestion.
@Suite("ColourCalibrationProcess: no default sensor, the OSC or mono route, INSTRUME offered")
struct ColourCalibrationRouteTests {
  struct Row: Sendable, CustomTestStringConvertible {
    let enabled: Bool
    let values: [String: String]
    let layerIDs: Set<String>
    let runsTool: Bool
    let unchosen: [String]
    var testDescription: String { "\(enabled) \(values) \(layerIDs.sorted())" }
  }

  static func params(enabled: Bool, _ values: [String: String]) throws -> ParamSet {
    var params = ParamSet(schema: ColourCalibrationProcess.schema)
    try params.set("enabled", .flag(enabled))
    for (id, value) in values.sorted(by: { $0.key < $1.key }) { try params.set(id, .choice(value)) }
    return params
  }

  static let mono: Set<String> = ["L", "R", "G", "B"]
  static let monoNames = [
    "monoSensor": "ZWO ASI1600MM", "rFilter": "Baader R", "gFilter": "Baader G",
    "bFilter": "Baader B",
  ]

  @Test(
    "testRunsTool: unticked runs nothing; ticked runs Siril, Apply waiting for the names to choose",
    arguments: [
      Row(enabled: false, values: [:], layerIDs: ["RGB"], runsTool: false, unchosen: []),
      Row(
        enabled: true, values: [:], layerIDs: ["RGB"], runsTool: true,
        unchosen: ["sensor", "filter"]),
      Row(
        enabled: true, values: ["sensor": "Sony IMX571"], layerIDs: ["RGB", "Ha"],
        runsTool: true, unchosen: ["filter"]),
      Row(
        enabled: true, values: ["sensor": "Sony IMX571", "filter": "UV/IR Block"],
        layerIDs: ["RGB"], runsTool: true, unchosen: []),
      Row(enabled: true, values: ["method": "pcc"], layerIDs: ["RGB"], runsTool: true, unchosen: []),
      Row(
        enabled: true, values: ["sensor": "Sony IMX571", "filter": "UV/IR Block"],
        layerIDs: mono, runsTool: true, unchosen: ["monoSensor", "rFilter", "gFilter", "bFilter"]),
      Row(enabled: true, values: monoNames, layerIDs: mono, runsTool: true, unchosen: []),
    ])
  func testRunsTool(row: Row) throws {
    let params = try Self.params(enabled: row.enabled, row.values)
    let type = ColourCalibrationProcess.self
    #expect(type.runsTool(params) == row.runsTool)
    #expect(type.unchosen(params, layerIDs: row.layerIDs) == row.unchosen)
  }

  @Test(
    "the mono route is a bundle without an OSC colour layer; no layer known reads as OSC",
    arguments: [
      (Set(["RGB"]), false), (Set(["RGB", "Ha", "OIII"]), false), (mono, true),
      (Set(["L", "Ha"]), true), (Set<String>(), false),
    ])
  func testMonoRoute(layerIDs: Set<String>, mono: Bool) {
    #expect(ColourCalibrationProcess.isMono(layerIDs: layerIDs) == mono)
  }

  @Test("the sensor and filter start unset, the white reference and method keep their defaults")
  func testNoCameraDefault() {
    let params = ParamSet(schema: ColourCalibrationProcess.schema)
    for id in ["sensor", "filter", "monoSensor", "rFilter", "gFilter", "bFilter"] {
      #expect(params.choice(id).isEmpty, "\(id)")
      #expect(ColourCalibrationProcess.schema.spec(id)?.allowsUnset == true, "\(id)")
    }
    #expect(params.choice("whiteReference") == "Average Spiral Galaxy")
    #expect(ColourCalibrationProcess.schema.problems.isEmpty)
  }

  @Test(
    "the header's camera is offered on the route's sensor, never set; none off the route",
    arguments: [
      ("ZWO ASI2600MC Air", Set(["RGB"]), [Suggestion(
        paramID: "sensor", value: .choice("Sony IMX571"),
        reason: ColourCalibrationProcess.fromHeader, subject: "ZWO ASI2600MC Air")]),
      ("ZWO ASI1600MM Pro", mono, [Suggestion(
        paramID: "monoSensor", value: .choice("ZWO ASI1600MM"),
        reason: ColourCalibrationProcess.fromHeader, subject: "ZWO ASI1600MM Pro")]),
      ("ZWO ASI1600MM Pro", Set(["RGB"]), []),
      ("Canon EOS R6", Set(["RGB"]), []),
    ])
  func testHeaderSuggestion(instrume: String, layerIDs: Set<String>, expected: [Suggestion]) {
    let header = FITSHeader(cards: [FITSHeader.Card(keyword: "INSTRUME", value: "'\(instrume)'")])
    #expect(
      ColourCalibrationProcess.suggestions(header: header, layerIDs: layerIDs) == expected)
    #expect(ColourCalibrationProcess.suggestions(header: nil, layerIDs: layerIDs).isEmpty)
    #expect(ColourCalibrationProcess.suggestionReasons == [ColourCalibrationProcess.fromHeader])
  }
}
