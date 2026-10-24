import AstroStackApp
import Foundation
import StackKit
import Testing

extension FrameReviewViewModelTests {
  /// The three ways a lane reaches the Tri stage (cards 0069, 0096).
  enum LaneKind: String, CaseIterable, Sendable {
    case live, reference, readOnly

    /// Lane L of `frames`, as this kind builds it.
    @MainActor func model(_ frames: PreprocessEvent.Frames) -> FrameReviewViewModel {
      switch self {
      case .live:
        return FrameReviewViewModel(frames: frames) { _ in }
      case .reference:
        let pause = PreprocessEvent.Reference(
          lane: "L", candidates: frames.grades, registered: [true, true, true, false],
          nights: frames.nights, parity: [.same, .same, .same, .unprobed], elected: 3,
          gate: ReferencePinGate(lane: "L"))
        return FrameReviewViewModel(reference: pause) { _ in }
      case .readOnly:
        var outcome = RunPanelTests.outcome("L", frames: 4)
        outcome.grades = frames.grades
        outcome.frameNights = frames.nights
        return FrameReviewViewModel(lane: GradesRecord.Lane(outcome))
      }
    }
  }

  @Test(
    "every lane kind opens each frame's capture; an unknown index or an empty path opens nothing",
    arguments: LaneKind.allCases)
  func testPreviewURL_rows(_ kind: LaneKind) {
    var frames = Self.frames()
    // `ChannelGrading` writes "" for a frame past the light list.
    frames.grades[3].path = ""
    let model = kind.model(frames)
    #expect(model.rows.map(\.index) == [1, 2, 3, 4])
    let expected: [Int: URL?] = [
      1: URL(fileURLWithPath: "/c/L/1.fits"), 2: URL(fileURLWithPath: "/c/L/2.fits"),
      3: URL(fileURLWithPath: "/c/L/3.fits"), 4: nil, 0: nil, 99: nil,
    ]
    for (index, url) in expected.sorted(by: { $0.key < $1.key }) {
      #expect(model.previewURL(of: index) == url, "frame \(index)")
    }
    #expect(model.previewURL(of: 2)?.isFileURL == true)
  }
}
