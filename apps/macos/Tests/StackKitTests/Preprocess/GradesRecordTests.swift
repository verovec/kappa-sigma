import Foundation
import StackKit
import TestSupport
import Testing

/// `grades.json` (card 0069): every lane's grades, nights, reference and the user's decision,
/// written beside the bundle by the run and read back by the Tri stage.
@Suite("GradesRecord — grades.json round trip, written by the run")
struct GradesRecordTests {
  static func result() -> PreprocessResult {
    var result = PreprocessResult(runID: "R1")
    var outcome = RunPanelOutcome.make("L", frames: 3)
    outcome.grades = (1...3).map { index in
      var grade = FrameGrade(index: index, path: "/c/L/\(index).fits")
      grade.fwhm = 2.5 + Double(index) / 10
      grade.wfwhm = grade.fwhm + 0.1
      grade.roundness = 0.9
      grade.starCount = 120 + index
      grade.background = 0.012
      grade.quality = 0.5
      grade.shiftX = Double(index)
      grade.shiftY = -Double(index)
      grade.trailScore = 0.05
      return grade
    }
    outcome.grades[1].rejected = true
    outcome.grades[1].rejectReason = ChannelGrading.userReason
    outcome.grades[2].trailDetected = true
    outcome.frameNights = ["2026-09-22", "2026-09-22", "2026-09-23"]
    outcome.reference = 3
    outcome.frameDecision = FrameDecision(exclude: [2], forceKeep: [3])
    var unreviewed = RunPanelOutcome.make("R", frames: 1)
    unreviewed.grades = [FrameGrade(index: 1, path: "/c/R/1.fits")]
    result.channels = [outcome, unreviewed]
    return result
  }

  @Test("the record of a result writes and reads back equal, every field kept", .scratchDirectory)
  func testGradesJSONRoundTrip() throws {
    let folder = try ScratchDirectory.url
    let record = GradesRecord(result: Self.result())
    #expect(record.runID == "R1" && record.lanes.map(\.lane) == ["L", "R"])
    #expect(record.lanes[0].reviewed && !record.lanes[1].reviewed)
    #expect(record.lanes[0].decision == FrameDecision(exclude: [2], forceKeep: [3]))
    #expect(record.lanes[0].reference == 3 && record.lanes[0].nights.count == 3)
    try record.write(to: folder)
    let read = try GradesRecord.read(from: folder)
    #expect(read == record)
    let text = try String(
      contentsOf: folder.appendingPathComponent(GradesRecord.fileName), encoding: .utf8)
    let compact = text.filter { !$0.isWhitespace }
    #expect(compact.contains("\"force_keep\":[3]") && compact.contains("\"run_id\":\"R1\""))
    #expect(
      compact.contains("\"reject_reason\":\"user\""), "snake_case keys, as the legacy records")
  }

  @Test("a run writes grades.json beside its bundle, one lane per channel", .scratchDirectory)
  func testRunWritesGrades() async throws {
    let request = try PreprocessorFrameReviewTests.request(frameReview: false)
    let (events, error) = await PreprocessorTests.collect(
      Preprocessor(tools: PreprocessorTests.tools(PreprocessorFrameReviewTests.siril())).run(
        request))
    #expect(error == nil && events.contains(where: PreprocessorTests.isFinished))
    let record = try GradesRecord.read(from: request.output)
    #expect(record.runID == "REVIEW" && record.lanes.map(\.lane) == ["L", "R"])
    #expect(record.lanes.allSatisfy { !$0.reviewed && $0.decision == nil })
    #expect(record.lanes[0].reference == 3 && record.lanes[0].grades.count == 3)
    #expect(record.lanes[1].grades[2].rejected)
  }
}

/// A channel outcome for a record test (the app's `RunPanelTests.outcome`, without the app).
enum RunPanelOutcome {
  static func make(_ filter: String, frames: Int) -> ChannelOutcome {
    let key = SetKey(
      type: .light, object: "M31", filter: filter, exposureMs: 300_000, gain: 100, offset: 50,
      tempBucketC: -10, bin: 1, session: "2026-09-22")
    var outcome = ChannelOutcome(
      FrameSet(key: key, frames: [], indices: []), filter: filter,
      selection: CalibrationSelection())
    outcome.inputFrames = frames
    return outcome
  }
}
