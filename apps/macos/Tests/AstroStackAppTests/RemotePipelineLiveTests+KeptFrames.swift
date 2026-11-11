import AstroStackApp
import Foundation
import StackKit
import TestSupport
import Testing

/// Card 0191: a second run of the same bucket night downloads nothing — the frames the first one
/// kept are linked into its lanes — and stacks to the same masters.
extension RemotePipelineLiveTests {
  @Test(
    "testKeptFramesSpareTheSecondRun: no download the second time, the same masters",
    .scratchDirectory)
  func testKeptFramesSpareTheSecondRun() async throws {
    try await Night.with { night in try await Self.keptFramesSpare(night) }
  }

  /// Two runs of `night` from the bucket over one cache, each into a library of its own so the
  /// second builds its masters again from the kept calibration frames.
  static func keptFramesSpare(_ night: Night) async throws {
    let cache = RemoteFrameCache(root: night.root.appendingPathComponent("remote-frames/P"))
    let first = try await night.imported()
    _ = try await night.run(first.inventory, "K_first", stores: first.stores, cache: cache)
    let downloaded = first.downloads.keys.withLock { $0 }
    #expect(!downloaded.isEmpty && cache.size() > 0, "the first run kept what it downloaded")

    let second = try await night.imported()
    _ = try await night.run(second.inventory, "K_second", stores: second.stores, cache: cache)

    #expect(second.downloads.keys.withLock { $0 }.isEmpty, "every frame came from the kept copies")
    #expect(
      try Self.masterDigests(in: night.root.appendingPathComponent("out-K_second"))
        == (try Self.masterDigests(in: night.root.appendingPathComponent("out-K_first"))),
      "the same frames, the same masters")
    #expect(
      !FileManager.default.fileExists(
        atPath: night.root.appendingPathComponent("work-K_second/light_L").path),
      "the lane's links went with it; the copies stay")
    #expect(cache.size() > 0)
  }
}
