import Foundation
import StackKit
import Testing

/// `ChannelGrading` is the legacy `gradeChannel` (`pipeline.go:2148`): metrics from the calibrated
/// sequence's `.seq`, frames Siril could not register rejected up front and left out of the
/// registered space, rejected frames mapped to 1-based indices in that space.
@Suite("ChannelGrading — from a .seq to the frames to unselect")
struct ChannelGradingTests {
  static func line(fwhm: Double, stars: Int = 30, roundness: Double = 0.95) -> String {
    "R0 \(fwhm) \(fwhm) \(roundness) 0 0.01 \(stars) H 1 0 0 0 1 0 0 0 1"
  }

  static func frames(_ count: Int) -> [CaptureFrame] {
    (0..<count).map { CaptureFrame(path: "/in/light_\($0).fits") }
  }

  @Test("an unregistered frame is rejected and absent from the registered numbering")
  func testUnregisteredFrame() throws {
    let text = [Self.line(fwhm: 3), "R0 0 0 0 0 0 0", Self.line(fwhm: 3.1), Self.line(fwhm: 9)]
      .joined(separator: "\n")
    let outcome = try ChannelGrading.grade(
      SirilSequence(parsing: text), frames: Self.frames(4),
      settings: .init(dropWheelTransition: false))
    #expect(outcome.registeredCount == 3)
    #expect(outcome.grades[1].rejected)
    #expect(outcome.grades[1].rejectReason == ChannelGrading.unregisteredReason)
    #expect(outcome.grades.map(\.path) == Self.frames(4).map(\.path))
    #expect(outcome.grades.map(\.index) == [1, 2, 3, 4])
    // Frame 4 is a soft-frame candidate but three frames are below the robust-rule minimum.
    #expect(outcome.rejectedRegistered.isEmpty)
  }

  @Test("an upstream rejection and a wheel transition keep their reasons; indices are registered")
  func testPreRejectAndTransition() throws {
    let text = (0..<6).map { _ in Self.line(fwhm: 3) }.joined(separator: "\n")
    var frames = Self.frames(6)
    frames[0].wheelTransition = true
    let outcome = try ChannelGrading.grade(
      SirilSequence(parsing: "R0 0 0 0 0 0 0\n" + text),
      frames: [CaptureFrame(path: "/x")] + frames,
      settings: .init(dropWheelTransition: true), preReject: [4: "transform review"])
    #expect(outcome.registeredCount == 6)
    #expect(outcome.grades[1].rejectReason == ChannelGrading.wheelTransitionReason)
    #expect(outcome.grades[4].rejectReason == "transform review")
    #expect(outcome.rejectedRegistered == [1, 4])
  }

  @Test("the trail probe is asked per registered frame and its verdict grades")
  func testTrailProbe() {
    let text = (0..<5).map { _ in Self.line(fwhm: 3) }.joined(separator: "\n")
    let outcome = ChannelGrading.grade(
      SirilSequence(parsing: text), frames: Self.frames(5), settings: .init(),
      trail: { index in index == 2 ? (true, 0.8) : (false, 0.1) })
    #expect(outcome.grades[2].trailDetected && outcome.grades[2].trailScore == 0.8)
    #expect(outcome.rejectedRegistered == [3])
    #expect(outcome.grades[0].trailScore == 0.1)
  }
}
