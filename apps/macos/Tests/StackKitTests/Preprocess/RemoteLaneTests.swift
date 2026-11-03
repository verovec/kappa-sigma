import Foundation
import StackKit
import Synchronization
import TestSupport
import Testing

/// Card 0154: a lane whose frames live in a bucket runs like a local one — the frames are
/// downloaded into the lane's own folder, go with it, and what identifies them is what the resume
/// digest compares. A download that fails fails its lane with the bucket's own words.
@Suite("Remote lanes — downloaded for the lane, dropped with it")
struct RemoteLaneTests {
  /// The golden night's L set with every frame moved into a bucket, and the bucket holding them.
  struct RemoteNight {
    let fixture: ChannelStackerTests.Fixture
    let bucket: FrameStagerTests.FakeBucket
    let lights: FrameSet

    static func make() async throws -> Self {
      let fixture = try await ChannelStackerTests.Fixture.make()
      let local = try fixture.lights
      var objects: [String: Data] = [:]
      var frames: [CaptureFrame] = []
      for frame in local.frames {
        let key = "M31/2026-10-18/" + PathMeta.baseName(frame.path)
        objects[key] = try Data(contentsOf: URL(fileURLWithPath: frame.path))
        var moved = frame
        moved.path = "s3://astro/" + key
        frames.append(moved)
      }
      let bucket = FrameStagerTests.FakeBucket(objects: objects)
      return Self(
        fixture: fixture, bucket: bucket,
        lights: FrameSet(key: local.key, frames: frames, indices: local.indices))
    }
  }

  @Test(
    "testRemoteLaneFolderRemoved: the downloads live in the lane's folder and go with it",
    .scratchDirectory)
  func testRemoteLaneFolderRemoved() async throws {
    let night = try await RemoteNight.make()
    let siril = PipelineSiril()
    var stacker = ChannelStacker(runner: siril.runner, trailProbe: { _, _ in (false, 0.1) })
    stacker.stager = FrameStager(stores: [night.bucket.store])

    let outcome = try await stacker.stack(
      night.lights, filter: "L", inventory: night.fixture.inventory,
      masters: night.fixture.masters, work: night.fixture.work, out: night.fixture.out)

    #expect(outcome.error == nil, "\(outcome.error ?? "")")
    #expect(night.bucket.downloaded.count == night.lights.frames.count, "every frame fetched once")
    let lane = night.fixture.work.appendingPathComponent("light_L")
    #expect(
      !FileManager.default.fileExists(atPath: lane.path),
      "the lane's folder — downloads and all — goes with the lane")
  }

  @Test(
    "a download that fails fails the lane with the bucket's words, and drops it", .scratchDirectory)
  func testDownloadFailureFailsTheLaneWithS3Text() async throws {
    let night = try await RemoteNight.make()
    night.bucket.fail(true)
    var stacker = ChannelStacker(
      runner: PipelineSiril().runner, trailProbe: { _, _ in (false, 0.1) })
    stacker.stager = FrameStager(stores: [night.bucket.store])

    let outcome = try await stacker.stack(
      night.lights, filter: "L", inventory: night.fixture.inventory,
      masters: night.fixture.masters, work: night.fixture.work, out: night.fixture.out)

    let error = try #require(outcome.error)
    #expect(outcome.masterPath == nil, "a lane that could not read its frames stacks nothing")
    #expect(
      !FileManager.default.fileExists(
        atPath: night.fixture.work.appendingPathComponent("light_L").path),
      "and leaves no half-downloaded folder: \(error)")
  }

  @Test("testRemoteDigestUsesETag: a frame re-uploaded under the same key re-runs its lane")
  func testRemoteDigestUsesETag() throws {
    let path = "s3://astro/M31/2026-10-18/l_1.fits"

    let first = LaneRecord.files([path], identities: [path: "2880|etag-one"])
    let same = LaneRecord.files([path], identities: [path: "2880|etag-one"])
    let reuploaded = LaneRecord.files([path], identities: [path: "2880|etag-two"])
    let unknown = LaneRecord.files([path])

    #expect(first == same, "the same bytes in the bucket: the lane is reused")
    #expect(first != reuploaded, "the same key, other bytes: the lane re-runs")
    #expect(unknown.contains(path), "a bucket that did not answer still names its frame")
    #expect(unknown != first, "and is not taken for a frame whose identity was read")
  }

  @Test("a local frame's digest is what it has always been", .scratchDirectory)
  func testLocalDigestUnchanged() throws {
    let root = try ScratchDirectory.url
    let paths = try FrameStagerTests.localFrames(2, in: root.appendingPathComponent("capture"))

    let withMap = LaneRecord.files(paths, identities: ["s3://astro/elsewhere.fits": "1|e"])
    let without = LaneRecord.files(paths)

    #expect(withMap == without, "an identity map for other frames changes nothing")
    #expect(without.contains(paths[0]) && without.contains(" "))
  }

  @Test("the scratch estimate adds a remote lane's raw bytes to that lane alone")
  func testScratchEstimateCountsTheDownloads() throws {
    var local = CaptureFrame(path: "/c/M31/l_1.fits")
    local.type = .light
    local.width = 1000
    local.height = 1000
    local.channels = 1
    var remote = local
    remote.path = "s3://astro/M31/l_2.fits"
    let localSet = FrameSet(key: SetKey(type: .light, filter: "L"), frames: [local], indices: [0])
    let remoteSet = FrameSet(key: SetKey(type: .light, filter: "L"), frames: [remote], indices: [0])

    #expect(ScratchEstimate.rawRemoteBytes(localSet) == 0, "a frame of this Mac is symlinked")
    #expect(
      ScratchEstimate.rawRemoteBytes(remoteSet) == 1000 * 1000 * 2,
      "a 16-bit frame downloads as its stored size")
    let mixed = ScratchEstimate.laneBytes([localSet, remoteSet], flatten: false)
    let localOnly = ScratchEstimate.laneBytes([localSet, localSet], flatten: false)
    #expect(mixed == localOnly + 1000 * 1000 * 2, "the downloads sit on top of Siril's copies")
  }
}
