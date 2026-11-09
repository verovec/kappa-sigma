import Foundation
import ImageKit
import Metal
import ProcessKit
import TestSupport
import Testing

/// Card 0187: `stepStats` is measured once per head and follows every move of the history — the
/// statistics the next step reads are always the head's, never a stale measure.
@Suite(
  "StudioSession — the step statistics follow the head",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct StudioSessionStepStatsTests {
  @Test("testStepStats_FollowsTheHead", .scratchDirectory)
  func testStepStats_FollowsTheHead() throws {
    let session = try StudioSessionChainTests.session("applied")
    #expect(session.stepStats == session.bundle.stats, "no step: the bundle's")

    try StudioSessionChainTests.applying([try StudioSessionChainTests.gain(1.5)], on: session)
    let afterOne = session.stepStats
    #expect(afterOne == LayerStats.measured(session.history.current))
    #expect(afterOne != session.bundle.stats)

    try StudioSessionChainTests.applying([try StudioSessionChainTests.gain(0.5)], on: session)
    let afterTwo = session.stepStats
    #expect(afterTwo == LayerStats.measured(session.history.current))
    #expect(afterTwo != afterOne)

    try session.history.undo()
    #expect(session.stepStats == afterOne, "back on step 1's output")
    try session.history.undo()
    #expect(session.stepStats == session.bundle.stats, "back on the original")
    try session.history.redo()
    #expect(session.stepStats == afterOne)
  }
}
