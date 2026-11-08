import AstroStackApp
import Foundation
import RemoteKit
import StackKit
import TestSupport
import Testing

/// Card 0186 against a real S3 service (`just s3-live`): a lane stacks the bytes its run listed.
/// An object uploaded again between the run's listing and the lane's download fails the lane,
/// named, and leaves nothing in the lane's folder; an unchanged one is staged as listed.
@Suite(
  "Live S3: a lane stacks what its run listed",
  .liveS3, .tags(.live), .serialized, .timeLimit(.minutes(2)))
struct LiveRemoteStagerTests {
  @Test(
    "an object uploaded again since the listing fails the lane; the other is staged",
    .scratchDirectory)
  func testChangedObjectFailsTheLane() async throws {
    let live = try #require(LiveS3Environment.current)
    let scratch = try ScratchDirectory.url
    let first = scratch.appendingPathComponent("first.fits")
    let again = scratch.appendingPathComponent("again.fits")
    try Data("frame, as listed".utf8).write(to: first)
    try Data("frame, uploaded again".utf8).write(to: again)

    try await live.withRun { client, prefix in
      for name in ["kept.fits", "changed.fits"] {
        _ = try await client.upload(file: first, bucket: live.bucket, key: prefix + name)
      }
      let store = RemoteObjectStore.s3(client, bucket: live.bucket)
      let kept = "s3://\(live.bucket)/\(prefix)kept.fits"
      let changed = "s3://\(live.bucket)/\(prefix)changed.fits"
      let listed = try await FrameStager(stores: [store]).identities(of: [kept, changed])
      #expect(listed.count == 2, "\(listed)")
      _ = try await client.upload(file: again, bucket: live.bucket, key: prefix + "changed.fits")

      let stager = FrameStager(stores: [store], expected: listed)
      let staged = try await stager.stage([kept], into: scratch.appendingPathComponent("ok"))
      #expect(staged.identities == [kept: listed[kept]], "an unchanged object is the one listed")

      let lane = scratch.appendingPathComponent("light_L")
      await #expect {
        try await stager.stage([changed], into: lane)
      } throws: { error in
        guard case PreprocessError.remoteFrameUnavailable(let path, _) = error else { return false }
        return path == changed
      }
      let left = (try? FileManager.default.contentsOfDirectory(atPath: lane.path)) ?? []
      #expect(left.isEmpty, "neither the changed frame nor a .part: \(left)")
    }
  }
}
