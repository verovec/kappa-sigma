import Foundation
import StackKit
import TestSupport
import Testing

/// `ChannelTrailMask` is `maskChannelTrails` + `summarizeTrailMask` (`pipeline/trailmask.go`):
/// the in-memory pass while the channel fits the budget, the streamed one above it, the cleaned
/// frames rewritten in place, one note in the legacy wording.
@Suite(
  "ChannelTrailMask — a channel's registered frames masked within the memory budget", .serialized)
struct ChannelTrailMaskTests {
  typealias Frames = TrailMaskFrames

  static func files() throws -> [URL] {
    try Frames.write(
      (0..<8).map { Frames.frame($0, amplitude: $0 == 2 ? 0.6 : 0) }, in: ScratchDirectory.url)
  }

  @Test(
    "in memory under the budget, streamed over it: the trail is painted either way",
    .scratchDirectory, arguments: [(Int64(1) << 34, nil as String?), (Int64(1) << 20, "streamed")])
  func testModes(budget: Int64, mode: String?) async throws {
    let urls = try Self.files()
    let masked = try #require(try await ChannelTrailMask.mask(urls, k: 3, budget: budget))
    #expect(masked.summary.segments >= 1 && masked.summary.frames == 8)
    #expect(masked.mode?.hasPrefix("streamed, 8-frame basis under a 0.0 GiB") ?? true)
    #expect((masked.mode == nil) == (mode == nil))
    #expect(Frames.maxAlongDiagonal(try Frames.read(urls[2])) < 0.2)
    #expect(masked.note.hasPrefix("cross-frame trail mask: cleaned "))
  }

  @Test("under five frames nothing runs", .scratchDirectory)
  func testTooFew() async throws {
    let urls = Array(try Self.files().prefix(4))
    #expect(try await ChannelTrailMask.mask(urls, k: 3, budget: 1 << 34) == nil)
  }

  @Test("the note: pixels, share, segments, rejections, then recurring, saturation, mode")
  func testNote() {
    var summary = TrailMaskSummary(
      frames: 10, framesWithTrails: 2, segments: 3, maskedPixels: 500, rejected: 1, recurring: 1)
    summary.saturatedPixels = 64
    #expect(
      ChannelTrailMask.note(summary, width: 100, height: 100, mode: "streamed, x")
        == "cross-frame trail mask: cleaned 500 pixels (0.50%) across 10 frames — 3 trail "
        + "segment(s) in 2 frame(s), 1 candidate(s) rejected as fixed pattern, 1 recurring "
        + "corridor(s) repaired, 64 sensor-saturated core px repaired from unsaturated nights "
        + "(streamed, x)")
  }
}
