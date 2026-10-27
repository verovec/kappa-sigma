import ImageKit
import ProcessKit
import Testing

/// Card 0140: no sensor chosen for the user — SPCC waits for its names, the route (OSC or mono)
/// is the visible `camera` row, the header's camera is only a suggestion.
@Suite("ColourCalibrationProcess: no default sensor, the OSC or mono route, INSTRUME offered")
struct ColourCalibrationRouteTests {
  struct Row: Sendable, CustomTestStringConvertible {
    let enabled: Bool
    let values: [String: String]
    let runsTool: Bool
    let unchosen: [String]
    var testDescription: String { "\(enabled) \(values.sorted { $0.key < $1.key })" }
  }

  static func params(enabled: Bool, _ values: [String: String]) throws -> ParamSet {
    var params = ParamSet(schema: ColourCalibrationProcess.schema)
    try params.set("enabled", .flag(enabled))
    for (id, value) in values.sorted(by: { $0.key < $1.key }) { try params.set(id, .choice(value)) }
    return params
  }

  static let osc = ["sensor": "Sony IMX571", "filter": "UV/IR Block"]
  static let mono = [
    "camera": "mono", "monoSensor": "ZWO ASI1600MM", "rFilter": "Baader R", "gFilter": "Baader G",
    "bFilter": "Baader B",
  ]

  @Test(
    "testRunsTool: unticked runs nothing; ticked runs Siril, Apply waiting for the names to choose",
    arguments: [
      Row(enabled: false, values: [:], runsTool: false, unchosen: []),
      Row(enabled: true, values: [:], runsTool: true, unchosen: ["sensor", "filter"]),
      Row(
        enabled: true, values: ["sensor": "Sony IMX571"], runsTool: true, unchosen: ["filter"]),
      Row(enabled: true, values: osc, runsTool: true, unchosen: []),
      Row(enabled: true, values: ["method": "pcc"], runsTool: true, unchosen: []),
      Row(
        enabled: true, values: osc.merging(["camera": "mono"]) { $1 }, runsTool: true,
        unchosen: ["monoSensor", "rFilter", "gFilter", "bFilter"]),
      Row(enabled: true, values: mono, runsTool: true, unchosen: []),
    ])
  func testRunsTool(row: Row) throws {
    let params = try Self.params(enabled: row.enabled, row.values)
    let type = ColourCalibrationProcess.self
    #expect(type.runsTool(params) == row.runsTool)
    #expect(type.unchosen(params) == row.unchosen)
  }

  @Test("the sensor and filters start unset, the route, white reference and method set")
  func testNoCameraDefault() {
    let params = ParamSet(schema: ColourCalibrationProcess.schema)
    for id in ColourCalibrationProcess.oscNames + ColourCalibrationProcess.monoNames {
      #expect(params.choice(id).isEmpty, "\(id)")
      #expect(ColourCalibrationProcess.schema.spec(id)?.allowsUnset == true, "\(id)")
    }
    #expect(params.choice("camera") == "osc" && !ColourCalibrationProcess.isMono(params))
    #expect(params.choice("whiteReference") == "Average Spiral Galaxy")
    #expect(ProcessRegistry.problems(of: ColourCalibrationProcess.self).isEmpty)
  }

  @Test(
    "only the rows Siril is told show: the route's names; under PCC no SPCC row",
    arguments: [
      ([String: String](), Set(ColourCalibrationProcess.monoNames)),
      (["camera": "mono"], Set(ColourCalibrationProcess.oscNames)),
      (
        ["method": "pcc"],
        Set(
          ["camera", "whiteReference"] + ColourCalibrationProcess.oscNames
            + ColourCalibrationProcess.monoNames)
      ),
    ])
  func testHiddenRows(values: [String: String], hidden: Set<String>) throws {
    let params = try Self.params(enabled: true, values)
    let type = ColourCalibrationProcess.self
    #expect(type.hiddenParameters(params, layerIDs: ["RGB"]) == hidden)
    #expect(type.hiddenParameters(params, layerIDs: ["L", "R", "G", "B"]) == hidden)
  }

  static func offer(_ camera: String, _ paramID: String, _ sensor: String, _ instrume: String)
    -> [Suggestion]
  {
    [("camera", camera), (paramID, sensor)].map { id, value in
      Suggestion(
        paramID: id, value: .choice(value), reason: ColourCalibrationProcess.fromHeader,
        subject: instrume)
    }
  }

  @Test(
    "the header's camera is offered with its route, never set; nothing for an unknown camera",
    arguments: [
      ("ZWO ASI2600MC Air", offer("osc", "sensor", "Sony IMX571", "ZWO ASI2600MC Air")),
      ("ZWO ASI1600MM Pro", offer("mono", "monoSensor", "ZWO ASI1600MM", "ZWO ASI1600MM Pro")),
      ("Canon EOS R6", []),
    ])
  func testHeaderSuggestion(instrume: String, expected: [Suggestion]) {
    let header = FITSHeader(cards: [FITSHeader.Card(keyword: "INSTRUME", value: "'\(instrume)'")])
    #expect(ColourCalibrationProcess.suggestions(header: header) == expected)
    #expect(ColourCalibrationProcess.suggestions(header: nil).isEmpty)
    #expect(ColourCalibrationProcess.suggestionReasons == [ColourCalibrationProcess.fromHeader])
  }
}
