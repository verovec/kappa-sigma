import Foundation
import StackKit
import TestSupport
import Testing

/// A lane's checkpoint (card 0097) on real data: measurements a real night yields (a NaN, an
/// infinite FWHM of a frame Siril could not measure) round-trip and never cost the reuse.
@Suite("LaneRecord — a real lane's outcome round-trips")
struct LaneRecordTests {
  @Test("NaN and infinite measurements are written and read back", .scratchDirectory)
  func testNonFiniteRoundTrip() throws {
    let output = try ScratchDirectory.url.appendingPathComponent("out")
    let key = SetKey(
      type: .light, object: "M 31", filter: "RGB", exposureMs: 300_000, gain: 100, offset: 50,
      tempBucketC: -10, bin: 1, session: "2026-09-22")
    var outcome = ChannelOutcome(
      FrameSet(key: key, frames: [], indices: []), filter: "RGB",
      selection: CalibrationSelection())
    var unmeasured = FrameGrade(index: 1, path: "/c/light_1.fits")
    unmeasured.fwhm = .infinity
    unmeasured.quality = .nan
    outcome.grades = [unmeasured]
    let request = PreprocessRequest(
      inventory: Inventory(root: "/c", frames: []), output: output, work: output, runID: "R")
    try LaneRecord(outcome, lane: "RGB", plan: NightPlan([]), request: request).write(to: output)

    let read = try LaneRecord.read(lane: "RGB", from: output)
    let grade = try #require(read.outcome.grades.first)
    #expect(grade.fwhm == .infinity && grade.quality.isNaN)
    #expect(read.outcome.filter == "RGB")
  }

  @Test("grades.json keeps the same non-finite measurements", .scratchDirectory)
  func testGradesNonFinite() throws {
    let folder = try ScratchDirectory.url.appendingPathComponent("out")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var result = PreprocessResult(runID: "R")
    var outcome = try Self.outcome()
    outcome.grades[0].background = -.infinity
    result.channels = [outcome]
    try GradesRecord(result: result).write(to: folder)
    let grade = try #require(try GradesRecord.read(from: folder).lanes.first?.grades.first)
    #expect(grade.fwhm == .infinity && grade.quality.isNaN && grade.background == -.infinity)
  }

  /// An RGB lane with one frame Siril could not measure.
  static func outcome() throws -> ChannelOutcome {
    let key = SetKey(
      type: .light, object: "M 31", filter: "RGB", exposureMs: 300_000, gain: 100, offset: 50,
      tempBucketC: -10, bin: 1, session: "2026-09-22")
    var outcome = ChannelOutcome(
      FrameSet(key: key, frames: [], indices: []), filter: "RGB",
      selection: CalibrationSelection())
    var unmeasured = FrameGrade(index: 1, path: "/c/light_1.fits")
    unmeasured.fwhm = .infinity
    unmeasured.quality = .nan
    outcome.grades = [unmeasured]
    return outcome
  }
}
