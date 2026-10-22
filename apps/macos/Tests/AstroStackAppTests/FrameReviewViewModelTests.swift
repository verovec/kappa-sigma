import AstroStackApp
import Foundation
import StackKit
import TestSupport
import Testing

/// The Tri stage's model (card 0069): one lane's grades as rows, the user's keep / reject toggles
/// as the exact decision the run applies, blink order following the sort, Continue once.
@MainActor
@Suite("FrameReviewViewModel — toggles, sort, blink and continue")
struct FrameReviewViewModelTests {
  /// Frames 1 and 3 kept (FWHM 2.5, 2.0), 2 auto-rejected (soft, FWHM 3.0), 4 unregistered.
  nonisolated static func frames(gate: FrameReviewGate = FrameReviewGate(lane: "L"))
    -> PreprocessEvent.Frames
  {
    var grades = (1...4).map { FrameGrade(index: $0, path: "/c/L/\($0).fits") }
    grades[0].fwhm = 2.5
    grades[1].fwhm = 3.0
    grades[2].fwhm = 2.0
    for index in 0..<3 {
      grades[index].roundness = 0.9
      grades[index].starCount = 100 + index
      grades[index].background = 0.01 * Double(index + 1)
    }
    grades[1].rejected = true
    grades[1].rejectReason = "soft frame (FWHM 3.00 vs median 2.50)"
    grades[3].rejected = true
    grades[3].rejectReason = ChannelGrading.unregisteredReason
    return PreprocessEvent.Frames(
      lane: "L", grades: grades, spans: [0..<4], nights: Array(repeating: "2026-09-22", count: 4),
      elected: 3, thumbnails: ["/t/1.png", "/t/2.png", "/t/3.png", nil], gate: gate)
  }

  struct Toggle: Sendable, CustomTestStringConvertible {
    let name: String
    let toggles: [Int]
    let expected: FrameDecision
    let kept: Int
    var testDescription: String { name }
  }

  nonisolated static let toggles: [Toggle] = [
    Toggle(name: "as graded", toggles: [], expected: FrameDecision(), kept: 2),
    Toggle(
      name: "reject a kept frame", toggles: [1], expected: FrameDecision(exclude: [1]), kept: 1),
    Toggle(
      name: "keep an auto-rejected frame", toggles: [2], expected: FrameDecision(forceKeep: [2]),
      kept: 3),
    Toggle(name: "toggle twice is as graded", toggles: [1, 1], expected: FrameDecision(), kept: 2),
    Toggle(
      name: "an unregistered frame cannot be kept", toggles: [4], expected: FrameDecision(), kept: 2
    ),
    Toggle(
      name: "both ways at once", toggles: [3, 2],
      expected: FrameDecision(exclude: [3], forceKeep: [2]), kept: 2),
  ]

  @Test("toggles serialise to the exact override fields; kept counts the stack", arguments: toggles)
  func testSortFilterToggle(_ row: Toggle) {
    let model = FrameReviewViewModel(frames: Self.frames()) { _ in }
    #expect(model.rows.map(\.id) == [1, 2, 3, 4] && model.isLive)
    #expect(model.rows.map(\.isKept) == [true, false, true, false])
    #expect(model.rows[3].isRegistered == false && model.elected == 3)
    for index in row.toggles { model.toggle(index) }
    #expect(model.decision == row.expected)
    #expect(model.keptCount == row.kept)
    #expect(model.canContinue == (row.kept >= 2))
  }

  @Test("keep and reject are idempotent and the rows show the verdict as the user left it")
  func testKeepReject() {
    let model = FrameReviewViewModel(frames: Self.frames()) { _ in }
    model.reject(1)
    model.reject(1)
    model.keep(2)
    model.keep(2)
    #expect(model.decision == FrameDecision(exclude: [1], forceKeep: [2]))
    #expect(model.rows.map(\.isKept) == [false, true, true, false])
    #expect(model.rows[0].isOverridden && model.rows[1].isOverridden && !model.rows[2].isOverridden)
    model.keep(1)
    model.reject(2)
    #expect(model.decision == FrameDecision())
  }

  @Test("the blink order follows the sort; unregistered frames sort last and never blink")
  func testBlinkFollowsSort() {
    let model = FrameReviewViewModel(frames: Self.frames()) { _ in }
    #expect(model.sortedRows.map(\.id) == [1, 2, 3, 4])
    #expect(model.current == 1, "blink starts on the first frame")
    model.blinkNext()
    #expect(model.current == 2)
    model.sortOrder = [KeyPathComparator(\.fwhm)]
    #expect(model.sortedRows.map(\.id) == [3, 1, 2, 4])
    model.blinkNext()
    #expect(model.current == 3, "after the frame shown, in the new order")
    model.blinkNext()
    model.blinkNext()
    #expect(model.current == 2)
    model.blinkNext()
    #expect(model.current == 3, "wraps; the unregistered frame has no thumbnail")
    model.blinkPrevious()
    #expect(model.current == 2)
    model.select(4)
    #expect(model.current == 4, "a row chosen in the table is shown even without a thumbnail")
    model.blinkNext()
    #expect(model.current == 3)
  }

  @Test("Continue hands the run the decision once; the model goes read-only")
  func testContinueOnce() {
    let gate = FrameReviewGate(lane: "L")
    let handed = Recorded<FrameDecision>()
    let model = FrameReviewViewModel(frames: Self.frames(gate: gate)) { handed.append($0) }
    model.toggle(1)
    #expect(!model.canContinue, "one frame kept is under Siril's stack minimum")
    model.continueStacking()
    #expect(handed.all.isEmpty)
    model.toggle(2)
    model.continueStacking()
    model.continueStacking()
    #expect(handed.all == [FrameDecision(exclude: [1], forceKeep: [2])])
    #expect(!model.isLive && !model.canContinue)
    model.toggle(3)
    #expect(
      model.decision == FrameDecision(exclude: [1], forceKeep: [2]), "read-only after Continue")
  }

  @Test("a lane read from grades.json is read-only and shows the verdicts as stacked")
  func testReadOnlyLane() {
    var outcome = RunPanelTests.outcome("L", frames: 4)
    outcome.grades = Self.frames().grades
    outcome.grades[0].rejected = true
    outcome.grades[0].rejectReason = ChannelGrading.userReason
    outcome.frameNights = Array(repeating: "2026-09-22", count: 4)
    outcome.reference = 3
    outcome.frameDecision = FrameDecision(exclude: [1])
    let model = FrameReviewViewModel(lane: GradesRecord.Lane(outcome))
    #expect(!model.isLive && !model.canContinue && model.elected == 3)
    #expect(model.rows.map(\.isKept) == [false, false, true, false])
    #expect(model.rows[0].isOverridden && model.rows[0].reason == ChannelGrading.userReason)
    #expect(model.current == nil && model.rows.allSatisfy { $0.thumbnail == nil })
    model.toggle(3)
    #expect(model.rows[2].isKept)
  }

  @Test("a metric histogram bins the registered frames over the metric's range")
  func testHistogram() {
    let model = FrameReviewViewModel(frames: Self.frames()) { _ in }
    let bins = model.histogram(\.fwhm, bins: 4)
    #expect(bins.count == 1 && bins[0].count == 4)
    #expect(bins[0].reduce(0, +) == 3, "the unregistered frame has no FWHM")
    #expect(bins[0] == [1, 0, 1, 1], "2.0 | · | 2.5 | 3.0 (the maximum lands in the last bin)")
  }
}
