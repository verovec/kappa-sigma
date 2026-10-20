import Foundation
import StackKit
import Testing

/// `ImportRequest` on the wire: the legacy `RunRequest` keys the Import page sent
/// (`internal/job/manager.go:174-327`), Go's `omitempty` included, and the scan overrides it
/// stands for.
@Suite("ImportRequest — the Import choices under the legacy request fields")
struct ImportRequestTests {
  static func object(_ request: ImportRequest) throws -> [String: Any] {
    let data = try JSONEncoder().encode(request)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  static let full: ImportRequest = {
    var request = ImportRequest(paths: ["/c/M31-DB", "/c/M31-BB"])
    request.filterMap = ["Ha": "ignore", "L": "L"]
    request.colorModel = .osc
    request.excludeSets = ["LIGHT|M 31|RGB|e300000|g100o50b1|i0|t-17|s:"]
    request.filterSets = ["LIGHT|M 31|RGB|e300000|g100o50b1|i0|t-17|s:": .dualband]
    request.calibExclude = ["dark|RGB|g100o50b1|e300000|t-17"]
    request.forceCalibration = true
    return request
  }()

  @Test("every choice serialises to the exact legacy field, and decodes back unchanged")
  func testOverridesRoundTrip() throws {
    let object = try Self.object(Self.full)
    #expect(
      Set(object.keys) == [
        "path", "paths", "filter_map", "color_model", "exclude_sets", "filter_set_overrides",
        "calib_exclude", "force_calibration_frames",
      ])
    #expect(object["path"] as? String == "/c/M31-DB")
    #expect(object["color_model"] as? String == "osc")
    #expect(
      object["filter_set_overrides"] as? [String: String]
        == ["LIGHT|M 31|RGB|e300000|g100o50b1|i0|t-17|s:": "dualband"])
    #expect(object["force_calibration_frames"] as? Bool == true)

    let decoded = try JSONDecoder().decode(
      ImportRequest.self, from: JSONEncoder().encode(Self.full))
    #expect(decoded == Self.full)
  }

  @Test("a default import is just its folder: Go's omitempty, `auto` colour left out")
  func testDefaultOmitsEmptyFields() throws {
    let object = try Self.object(ImportRequest(paths: ["/c/M31-DB"]))
    #expect(object.keys.sorted() == ["path"])
  }

  @Test(
    "a legacy body decodes: `path` alone is one folder, `paths` wins when present",
    arguments: [
      (#"{"path":"/c/A"}"#, ["/c/A"]),
      (#"{"path":"/c/A","paths":["/c/A","/c/B"]}"#, ["/c/A", "/c/B"]),
    ])
  func testDecodesLegacyBody(json: String, paths: [String]) throws {
    let request = try JSONDecoder().decode(ImportRequest.self, from: Data(json.utf8))
    #expect(request.paths == paths)
    #expect(request.overrides == InspectOverrides())
  }

  @Test(
    "unknown wire values are refused, never guessed",
    arguments: [
      #"{"path":"/c","color_model":"rgb"}"#, #"{"path":"/c","filter_set_overrides":{"x":"uv"}}"#,
    ]
  )
  func testRejectsUnknownValues(json: String) {
    #expect(throws: InspectError.self) {
      try JSONDecoder().decode(ImportRequest.self, from: Data(json.utf8))
    }
  }

  @Test("the scan sees exactly the request's overrides")
  func testOverridesProjection() {
    let overrides = Self.full.overrides
    #expect(overrides.filterMap == Self.full.filterMap)
    #expect(overrides.excludeSets == Self.full.excludeSets)
    #expect(overrides.filterSets == Self.full.filterSets)
    #expect(overrides.colorModel == .osc)
    #expect(overrides.detectChannels)
  }
}
