import AstroStackApp
import Foundation
import StackKit
import Testing

/// `StackRecord` (card 0095): the run scope rides in `params_json` beside the request, the preset
/// and the knobs, so a replay keeps the same series; a record without one reads as unscoped.
@MainActor
@Suite("StackRecord — the run scope recorded with the request")
struct StackRecordTests {
  static func json(_ record: StackRecord) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try #require(String(bytes: try encoder.encode(record), encoding: .utf8))
  }

  @Test("the scope round-trips under its own key and is left out when nil")
  func testScopeRoundTrip() throws {
    var record = StackRecord(
      request: ImportRequest(paths: ["/c/M31-DB", "/c/IC1848"]), mode: .nebula)
    #expect(record.scope == nil)
    #expect(
      try Self.json(record)
        == #"{"mode":"nebula","path":"\/c\/M31-DB","paths":["\/c\/M31-DB","\/c\/IC1848"]}"#)

    record.scope = RunScope(
      object: "M 31", setIDs: ["light|M 31|RGB|e120000|g100o50b1|i0|t-10|s:2026-09-22"], lights: 36)
    let json = try Self.json(record)
    #expect(json.contains(#""scope":{"lights":36,"object":"M 31","set_ids":["#))
    let decoded = try JSONDecoder().decode(StackRecord.self, from: Data(json.utf8))
    #expect(decoded == record)
    #expect(decoded.scope?.object == "M 31" && decoded.scope?.lights == 36)
  }

  @Test("a record written before 0095 reads as unscoped, its request and knobs intact")
  func testRecordWithoutScope() throws {
    let record = try JSONDecoder().decode(
      StackRecord.self,
      from: Data(#"{"path": "/c/M31-DB", "mode": "deepsky", "knobs": {"fwhm_sigma": 3.5}}"#.utf8))
    #expect(record.scope == nil)
    #expect(record.request.paths == ["/c/M31-DB"] && record.mode == .deepsky)
    #expect(record.knobs == KnobPatch(values: ["fwhm_sigma": .number(3.5)]))
  }
}
