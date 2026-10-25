import AstroStackApp
import Foundation
import StackKit
import Testing

/// The stack record's frame review (card 0069): the user's decisions per lane travel in
/// `params_json` under `frame_review`; absent, the run was not reviewed.
@MainActor
@Suite("StackRecord — the frame-review decisions round-trip in params_json")
struct StackRecordTests {
  @Test("decisions per lane encode under frame_review and decode back; absent means unreviewed")
  func testFrameOverridesRoundTrip() throws {
    var record = StackRecord(request: ImportRequest(paths: ["/c/M31-DB"]))
    record.frameReview = [
      "L": FrameDecision(exclude: [2, 5], forceKeep: [7]), "RGB": FrameDecision(),
    ]
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json = try #require(String(bytes: try encoder.encode(record), encoding: .utf8))
    #expect(
      json
        == #"{"frame_review":{"L":{"exclude":[2,5],"force_keep":[7]},"#
        + #""RGB":{"exclude":[],"force_keep":[]}},"mode":"deepsky","path":"\/c\/M31-DB"}"#)
    let decoded = try JSONDecoder().decode(StackRecord.self, from: Data(json.utf8))
    #expect(decoded == record)
    #expect(decoded.framesReviewed)

    let reviewedUntouched = try JSONDecoder().decode(
      StackRecord.self, from: Data(#"{"path": "/c/M31-DB", "frame_review": {}}"#.utf8))
    #expect(reviewedUntouched.framesReviewed && reviewedUntouched.frameReview == [:])
    let unreviewed = try JSONDecoder().decode(
      StackRecord.self, from: Data(#"{"path": "/c/M31-DB"}"#.utf8))
    #expect(!unreviewed.framesReviewed && unreviewed.frameReview == nil)
  }

  @Test("the reference pins per lane encode under reference_pins and decode back (card 0096)")
  func testReferencePinsRoundTrip() throws {
    var record = StackRecord(request: ImportRequest(paths: ["/c/M31-DB"]))
    record.referencePins = ["RGB": 67]
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json = try #require(String(bytes: try encoder.encode(record), encoding: .utf8))
    #expect(json == #"{"mode":"deepsky","path":"\/c\/M31-DB","reference_pins":{"RGB":67}}"#)
    let decoded = try JSONDecoder().decode(StackRecord.self, from: Data(json.utf8))
    #expect(decoded == record && !decoded.framesReviewed, "a pin alone is no frame review")
    let none = try JSONDecoder().decode(
      StackRecord.self, from: Data(#"{"path": "/c/M31-DB"}"#.utf8))
    #expect(none.referencePins == nil)
  }

  @Test("lane knobs and the processing choice encode under lane_knobs and processing (card 0121)")
  func testOverridesAndProcessingRoundTrip() throws {
    var record = StackRecord(request: ImportRequest(paths: ["/c/M31-DB"]))
    record.laneKnobs = [.dualband: KnobPatch(values: ["stack_reject": .choice("sigma")])]
    record.processing = .perChannel
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json = try #require(String(bytes: try encoder.encode(record), encoding: .utf8))
    #expect(
      json
        == #"{"lane_knobs":{"dualband":{"stack_reject":"sigma"}},"mode":"deepsky","#
        + #""path":"\/c\/M31-DB","processing":"per_channel"}"#)
    #expect(try JSONDecoder().decode(StackRecord.self, from: Data(json.utf8)) == record)
    // Untouched: neither key is written, and a record without them reads as one flow.
    let untouched = StackRecord(request: ImportRequest(paths: ["/c/M31-DB"]))
    let plain = try #require(String(bytes: try encoder.encode(untouched), encoding: .utf8))
    #expect(plain == #"{"mode":"deepsky","path":"\/c\/M31-DB"}"#)
    let decoded = try JSONDecoder().decode(StackRecord.self, from: Data(plain.utf8))
    #expect(decoded.laneKnobs.isEmpty && decoded.processing == .single)
  }

  @Test("a lane_knobs key naming no lane is kept aside and shown; the record still reads")
  func testUnknownLaneKeyShown() throws {
    let json =
      #"{"path": "/c/M31", "lane_knobs": {"narrowband": {"fwhm_sigma": 2}, "unknown": {}, "#
      + #""dualband": {"fwhm_sigma": 2}}}"#
    let record = try JSONDecoder().decode(StackRecord.self, from: Data(json.utf8))
    #expect(record.laneKnobs == [.dualband: KnobPatch(values: ["fwhm_sigma": .number(2)])])
    #expect(record.ignoredEntries == ["lane_knobs.narrowband", "lane_knobs.unknown"])
  }

  @Test("a processing this build does not know reads as one flow and is shown")
  func testUnknownProcessingShown() throws {
    let record = try JSONDecoder().decode(
      StackRecord.self, from: Data(#"{"path": "/c/M31", "processing": "per_lane"}"#.utf8))
    #expect(record.processing == .single && record.ignoredEntries == ["processing=per_lane"])
  }
}
