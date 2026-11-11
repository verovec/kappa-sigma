import Foundation
import StackKit
import TestSupport
import Testing

/// Card 0191: the frames a run downloads from a bucket are kept between runs — staged as links
/// to one copy a project, read again only when the bucket no longer holds the object listed.
@Suite("FrameStager — a bucket's frames kept between runs")
struct FrameStagerCacheTests {
  typealias FakeBucket = FrameStagerTests.FakeBucket

  static let keys = ["M31/n1/r_1.fits", "M31/n1/r_2.fits"]
  static let paths = keys.map { "s3://astro/" + $0 }

  static func bucket() -> FakeBucket {
    FakeBucket(objects: [keys[0]: Data("remote one".utf8), keys[1]: Data("remote two".utf8)])
  }

  /// A stager of `bucket` checking against a listing made now, keeping its downloads in `cache`.
  static func stager(_ bucket: FakeBucket, cache: RemoteFrameCache?) async throws -> FrameStager {
    let listed = try await FrameStager(stores: [bucket.store]).identities(of: paths)
    return FrameStager(stores: [bucket.store], expected: listed, cache: cache)
  }

  /// What the staged files read, in order.
  static func bytes(_ staged: FrameStager.Staged) throws -> [String] {
    try staged.files.map { try String(contentsOf: $0, encoding: .utf8) }
  }

  @Test("testStage_SecondRun_DownloadsNothing: the lane goes, the frames stay", .scratchDirectory)
  func testStage_SecondRun_DownloadsNothing() async throws {
    let root = try ScratchDirectory.url
    let cache = RemoteFrameCache(root: root.appendingPathComponent("remote-frames/P"))
    let bucket = Self.bucket()

    let lane = root.appendingPathComponent("run_1/light_L")
    let first = try await Self.stager(bucket, cache: cache).stage(Self.paths, into: lane)
    #expect(first.remote == 2 && first.cached == 0 && bucket.downloaded.count == 2)
    #expect(try Self.bytes(first) == ["remote one", "remote two"])
    // The lane's cleanup: its folder goes, as `ChannelStacker` removes it.
    try FileManager.default.removeItem(at: root.appendingPathComponent("run_1"))

    let again = root.appendingPathComponent("run_2/light_L")
    let second = try await Self.stager(bucket, cache: cache).stage(Self.paths, into: again)

    #expect(bucket.downloaded.count == 2, "nothing is downloaded a second time")
    #expect(second.remote == 0 && second.bytes == 0 && second.cached == 2)
    #expect(try Self.bytes(second) == ["remote one", "remote two"])
    #expect(second.identities == first.identities, "the resume digest reads the same frames")
    #expect(
      try FileManager.default.contentsOfDirectory(atPath: again.path).sorted()
        == ["00001_r_1.fits", "00002_r_2.fits"], "the names Siril reads are today's")
    #expect(cache.size() == Int64("remote one".utf8.count + "remote two".utf8.count))
  }

  /// What makes a kept frame unusable for a run.
  enum Stale: String, CaseIterable, Sendable {
    case changedInTheBucket, fileGone, identityGone
  }

  @Test(
    "testStage_StaleCopy_DownloadsAgain: only the object the run listed is stacked",
    .scratchDirectory, arguments: Stale.allCases)
  func testStage_StaleCopy_DownloadsAgain(stale: Stale) async throws {
    let root = try ScratchDirectory.url.appendingPathComponent(stale.rawValue)
    let cache = RemoteFrameCache(root: root.appendingPathComponent("remote-frames/P"))
    let bucket = Self.bucket()
    try await Self.stager(bucket, cache: cache).stage(
      Self.paths, into: root.appendingPathComponent("run_1/light_L"))
    let kept = cache.file(bucket: "astro", key: Self.keys[0])
    #expect(FileManager.default.fileExists(atPath: kept.path))

    switch stale {
    case .changedInTheBucket: bucket.replace(Self.keys[0], with: Data("uploaded again".utf8))
    case .fileGone: try FileManager.default.removeItem(at: kept)
    case .identityGone: try FileManager.default.removeItem(at: cache.identityFile(of: kept))
    }
    let second = try await Self.stager(bucket, cache: cache).stage(
      Self.paths, into: root.appendingPathComponent("run_2/light_L"))

    // The first run's two downloads end in either order; the third read is that frame alone.
    #expect(bucket.downloaded.count == 3 && bucket.downloaded.last == Self.keys[0])
    #expect(second.remote == 1 && second.cached == 1)
    let expected = stale == .changedInTheBucket ? "uploaded again" : "remote one"
    #expect(try Self.bytes(second) == [expected, "remote two"])
    #expect(try String(contentsOf: kept, encoding: .utf8) == expected, "the kept copy follows")
  }

  @Test("a download that fails keeps nothing: no half frame for the next run", .scratchDirectory)
  func testStage_Failure_KeepsNothing() async throws {
    let root = try ScratchDirectory.url
    let cache = RemoteFrameCache(root: root.appendingPathComponent("remote-frames/P"))
    let bucket = Self.bucket()
    let stager = try await Self.stager(bucket, cache: cache)
    bucket.fail(true)

    await #expect(throws: (any Error).self) {
      try await stager.stage(Self.paths, into: root.appendingPathComponent("run_1/light_L"))
    }

    #expect(cache.size() == 0)
    let left =
      FileManager.default.enumerator(at: cache.root, includingPropertiesForKeys: nil)?
      .compactMap { ($0 as? URL)?.pathExtension }.filter { !$0.isEmpty } ?? []
    #expect(left.isEmpty, "neither a frame, nor a .part, nor an identity: \(left)")
  }

  @Test(
    "a key cannot name a file outside the project's copies",
    arguments: ["../../x.fits", "a/../../../x.fits", "/abs/x.fits", "a//b/./x.fits", ".."])
  func testFile_StaysUnderTheRoot(key: String) {
    let cache = RemoteFrameCache(root: URL(fileURLWithPath: "/scratch/remote-frames/P"))
    let file = cache.file(bucket: "astro", key: key).standardizedFileURL.path
    #expect(file.hasPrefix("/scratch/remote-frames/P/astro/"), "\(file)")
  }

  @Test("a path of the project's copies is known as one; anything else is not")
  func testHolds() {
    let cache = RemoteFrameCache(root: URL(fileURLWithPath: "/scratch/remote-frames/P"))
    #expect(cache.holds("s3://astro/M31/n1/r_1.fits") == false, "nothing downloaded yet")
    #expect(cache.size() == 0, "a root that does not exist weighs nothing")
  }
}
