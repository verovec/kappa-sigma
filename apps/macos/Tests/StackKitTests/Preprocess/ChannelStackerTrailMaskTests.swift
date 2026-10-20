import Foundation
import StackKit
import TestSupport
import Testing

/// `ChannelStacker.maskRegistered` is `applyTrailMask`: the registered frames cleaned before the
/// stack at the preset's k, recorded on the channel, soft-failing.
@Suite("ChannelStacker trail mask — the registered frames cleaned before the stack", .serialized)
struct ChannelStackerTrailMaskTests {
  typealias F = TrailMaskFrames

  static func outcome() -> ChannelOutcome {
    let key = SetKey(
      type: .light, object: "T", filter: "L", exposureMs: 1000, gain: 0, offset: 0,
      tempBucketC: 0, bin: 1, session: "2026-01-01")
    return ChannelOutcome(
      FrameSet(key: key, frames: [], indices: []), filter: "L",
      selection: CalibrationSelection())
  }

  static func stacker(k: Double) -> ChannelStacker {
    var settings = PreprocessSettings()
    settings.trailMaskK = k
    return ChannelStacker(runner: PipelineSiril().runner, settings: settings)
  }

  @Test("deepsky and nebula mask at k = 3, as the legacy presets did")
  func testPresetK() {
    #expect(PreprocessSettings().trailMaskK == 3 && PreprocessSettings.preset(.nebula).trailMaskK == 3)
  }

  @Test("at k = 3 the trailed frame is cleaned, recorded and noted", .scratchDirectory)
  func testMasked() async throws {
    let urls = try F.write(
      (0..<8).map { F.frame($0, amplitude: $0 == 5 ? 0.6 : 0) }, in: ScratchDirectory.url)
    var outcome = Self.outcome()
    try await Self.stacker(k: 3).maskRegistered(urls, saturationCeilings: [], into: &outcome)
    let summary = try #require(outcome.trailMask)
    #expect(summary.segments >= 1 && summary.frames == 8 && summary.saturatedPixels == 0)
    #expect(outcome.selection.notes.last?.hasPrefix("cross-frame trail mask: cleaned ") == true)
    #expect(F.maxAlongDiagonal(try F.read(urls[5])) < 0.2)
  }

  @Test("k = 0 and no saturation repair: nothing runs, nothing is noted", .scratchDirectory)
  func testOff() async throws {
    let urls = try F.write(
      (0..<8).map { F.frame($0, amplitude: $0 == 5 ? 0.6 : 0) }, in: ScratchDirectory.url)
    var outcome = Self.outcome()
    try await Self.stacker(k: 0).maskRegistered(urls, saturationCeilings: [], into: &outcome)
    #expect(outcome.trailMask == nil && outcome.selection.notes.isEmpty)
    #expect(F.maxAlongDiagonal(try F.read(urls[5])) > 0.5)
  }

  @Test("an unreadable frame skips the mask with a note; the stack goes on", .scratchDirectory)
  func testSoftFail() async throws {
    var urls = try F.write((0..<6).map { F.frame($0) }, in: ScratchDirectory.url)
    urls[3] = try ScratchDirectory.url.appendingPathComponent("missing.fits")
    var outcome = Self.outcome()
    try await Self.stacker(k: 3).maskRegistered(urls, saturationCeilings: [], into: &outcome)
    #expect(outcome.trailMask == nil)
    #expect(outcome.selection.notes.first?.hasPrefix("trail mask skipped: ") == true)
  }
}
