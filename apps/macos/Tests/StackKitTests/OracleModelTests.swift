import Foundation
import StackKit
import Testing

@Suite("Oracle models decode the legacy engine's JSON faithfully")
struct OracleModelTests {
  static func decode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(type, from: Data(json.utf8))
  }

  static func master(hasTemp: Bool, milliC: Int) -> String {
    """
    {"type": "DARK", "exposure_ms": 300000, "gain": 100, "offset": 50, "bin": 1,
     "temp_milli_c": \(milliC), "has_temp": \(hasTemp), "path": "<ROOT>/m.fits"}
    """
  }

  @Test(
    "a master's temperature exists only when has_temp says so",
    arguments: [(true, -19_000, Optional(-19_000)), (false, 0, nil), (true, 0, Optional(0))])
  func testOracleMaster_temperature(hasTemp: Bool, milliC: Int, expected: Int?) throws {
    let decoded = try Self.decode(
      OracleMaster.self, Self.master(hasTemp: hasTemp, milliC: milliC))
    #expect(decoded.temperatureMilliC == expected)
  }

  @Test(
    "dark_optimize (scale a different-exposure dark) defaults to false when omitted",
    arguments: [(#"{"dark_optimize": true}"#, true), ("{}", false)])
  func testOracleSelection_darkOptimize(json: String, expected: Bool) throws {
    let selection = try Self.decode(OracleCalibration.Selection.self, json)
    #expect(selection.darkOptimize == expected)
  }
}
