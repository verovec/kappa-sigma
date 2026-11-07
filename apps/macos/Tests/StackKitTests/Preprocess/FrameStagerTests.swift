import Foundation
import StackKit
import Synchronization
import TestSupport
import Testing

/// Card 0154: a lane's frames are put where Siril reads them — a symlink for a frame of this Mac
/// (exactly today's, so scripts and masters stay byte-identical), a download for one that lives in
/// a bucket, and nothing left behind when it fails.
@Suite("FrameStager — a lane's frames where Siril reads them")
struct FrameStagerTests {
  /// A bucket whose objects are scripted, every download recorded.
  final class FakeBucket: Sendable {
    let bucket: String
    /// What the bucket holds and what it was asked.
    struct State {
      var objects: [String: Data] = [:]
      /// Each object's ETag: « e » as first stored, a new one on every `replace` — what S3 does
      /// when a key is uploaded again.
      var etags: [String: String] = [:]
      var uploads = 0
      var downloaded: [String] = []
      var listed: [String] = []
      var failure = false
      var listingFailure = false
    }

    private let state = Mutex(State())
    /// Whether the store downloads whole objects itself, as the S3 one does; without it,
    /// `RemoteObjectStore.download` writes `get` out through its own `.part`.
    let fetching: Bool

    init(bucket: String = "astro", objects: [String: Data], fetching: Bool = true) {
      self.bucket = bucket
      self.fetching = fetching
      state.withLock {
        $0.objects = objects
        $0.etags = objects.mapValues { _ in "e" }
      }
    }

    /// Uploads `data` again under `key`: a new ETag, as a real bucket gives it.
    func replace(_ key: String, with data: Data) {
      state.withLock {
        $0.uploads += 1
        $0.objects[key] = data
        $0.etags[key] = "e\($0.uploads)"
      }
    }

    var downloaded: [String] { state.withLock { $0.downloaded } }
    /// The prefixes this bucket was asked to list, in order.
    var listed: [String] { state.withLock { $0.listed } }

    func fail(_ failing: Bool) { state.withLock { $0.failure = failing } }

    func failListing(_ failing: Bool) { state.withLock { $0.listingFailure = failing } }

    var store: RemoteObjectStore {
      // A whole object answers with the ETag the listing gives, as `S3Client.download` does:
      // what a build read can be compared with what a run listed.
      let fetch: Fetch = { key, destination in
        let (data, etag) = try self.read(key)
        try data.write(to: destination, options: .atomic)
        return RemoteObjectStore.Object(key: key, size: Int64(data.count), etag: etag)
      }
      return RemoteObjectStore(
        bucket: bucket,
        list: { prefix in
          try self.state.withLock { state -> [RemoteObjectStore.Object] in
            state.listed.append(prefix)
            if state.listingFailure { throw CocoaError(.fileReadNoPermission) }
            return state.objects.filter { $0.key.hasPrefix(prefix) }.map {
              RemoteObjectStore.Object(
                key: $0.key, size: Int64($0.value.count), etag: state.etags[$0.key] ?? "e")
            }
          }
        },
        get: { key, _ in try self.read(key).data }, fetch: fetching ? fetch : nil)
    }

    /// A whole-object download, as `RemoteObjectStore` takes it.
    typealias Fetch = @Sendable (String, URL) async throws -> RemoteObjectStore.Object

    /// One read of `key`, recorded: its bytes and ETag, or the failure the test scripted.
    private func read(_ key: String) throws -> (data: Data, etag: String) {
      let object = state.withLock { state -> (Data, String)? in
        state.downloaded.append(key)
        guard !state.failure, let data = state.objects[key] else { return nil }
        return (data, state.etags[key] ?? "e")
      }
      guard let object else { throw CocoaError(.fileNoSuchFile) }
      return object
    }
  }

  /// `count` frames on disk under `folder`, and their paths.
  static func localFrames(_ count: Int, in folder: URL, prefix: String = "l") throws -> [String] {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return try (0..<count).map { index in
      let url = folder.appendingPathComponent("\(prefix)_\(index).fits")
      try Data("frame \(index)".utf8).write(to: url)
      return url.path
    }
  }

  @Test(
    "testLocalFramesAreTodaysLinks: the same names, pointing at the same frames", .scratchDirectory)
  func testLocalFramesAreTodaysLinks() async throws {
    let root = try ScratchDirectory.url
    let paths = try Self.localFrames(3, in: root.appendingPathComponent("capture"))
    let staged = root.appendingPathComponent("light_L")
    let expected = root.appendingPathComponent("light_L_today")
    try MasterBuilder.link(paths, into: expected)

    try await FrameStager().stage(paths, into: staged)

    let files = FileManager.default
    let names = try files.contentsOfDirectory(atPath: staged.path).sorted()
    #expect(names == (try files.contentsOfDirectory(atPath: expected.path).sorted()))
    #expect(names == ["00001_l_0.fits", "00002_l_1.fits", "00003_l_2.fits"])
    for name in names {
      let link = staged.appendingPathComponent(name).path
      #expect(
        try files.destinationOfSymbolicLink(atPath: link)
          == (try files.destinationOfSymbolicLink(
            atPath: expected.appendingPathComponent(name).path)),
        "\(name) points where today's link points")
    }
  }

  @Test(
    "testRemoteFramesDownloaded: a bucket's frames land under the same names", .scratchDirectory)
  func testRemoteFramesDownloaded() async throws {
    let root = try ScratchDirectory.url
    let local = try Self.localFrames(1, in: root.appendingPathComponent("capture"))
    let bucket = FakeBucket(objects: [
      "M31/2026-10-18/r_1.fits": Data("remote one".utf8),
      "M31/2026-10-18/r_2.fits": Data("remote two".utf8),
    ])
    // Mixed: a frame of this Mac and two of the bucket, in the order the lane lists them.
    let paths = [
      "s3://astro/M31/2026-10-18/r_1.fits", local[0], "s3://astro/M31/2026-10-18/r_2.fits",
    ]
    let staged = root.appendingPathComponent("light_L")

    let result = try await FrameStager(stores: [bucket.store]).stage(paths, into: staged)

    let files = FileManager.default
    #expect(
      try files.contentsOfDirectory(atPath: staged.path).sorted()
        == ["00001_r_1.fits", "00002_l_0.fits", "00003_r_2.fits"],
      "names are positional: the lane's order is the sequence's order")
    #expect(
      try Data(contentsOf: staged.appendingPathComponent("00001_r_1.fits"))
        == Data("remote one".utf8))
    #expect(
      try files.destinationOfSymbolicLink(
        atPath: staged.appendingPathComponent("00002_l_0.fits").path)
        == local[0], "the local frame is still a symlink, never a copy")
    #expect(bucket.downloaded.count == 2, "only the remote ones are fetched")
    #expect(result.remote == 2 && result.bytes > 0)
  }

  @Test("a download that fails leaves no .part and no half-staged folder", .scratchDirectory)
  func testFailedDownloadLeavesNothing() async throws {
    let root = try ScratchDirectory.url
    let bucket = FakeBucket(objects: ["M31/r_1.fits": Data("one".utf8)])
    bucket.fail(true)
    let staged = root.appendingPathComponent("light_L")

    await #expect(throws: (any Error).self) {
      try await FrameStager(stores: [bucket.store]).stage(
        ["s3://astro/M31/r_1.fits"], into: staged)
    }

    let left = (try? FileManager.default.contentsOfDirectory(atPath: staged.path)) ?? []
    #expect(left.allSatisfy { !$0.hasSuffix(".part") }, "no half-written frame: \(left)")
    #expect(!left.contains("00001_r_1.fits"), "and no frame that was never downloaded")
  }

  @Test("a remote frame with no bucket of its own is refused, never silently skipped")
  func testUnknownBucketIsRefused() async throws {
    await #expect(throws: (any Error).self) {
      try await FrameStager().stage(
        ["s3://astro/M31/r_1.fits"], into: URL(fileURLWithPath: "/tmp/never"))
    }
  }

  @Test("progress is told once every few frames and on the last one", .scratchDirectory)
  func testProgressIsReported() async throws {
    let root = try ScratchDirectory.url
    var objects: [String: Data] = [:]
    for index in 0..<10 { objects["M31/r_\(index).fits"] = Data("frame \(index)".utf8) }
    let bucket = FakeBucket(objects: objects)
    let paths = (0..<10).map { "s3://astro/M31/r_\($0).fits" }
    let seen = Mutex<[(done: Int, total: Int)]>([])

    _ = try await FrameStager(stores: [bucket.store]).stage(
      paths, into: root.appendingPathComponent("light_L")
    ) { done, total, _ in seen.withLock { $0.append((done, total)) } }

    let steps = seen.withLock { $0 }
    #expect(steps.last?.done == 10 && steps.last?.total == 10, "the last frame is always told")
    #expect(steps.count < 10, "not one line per frame: \(steps.count)")
    #expect(steps.allSatisfy { $0.total == 10 })
  }

  @Test("the identities come from one listing per bucket, over the prefix its keys share")
  func testIdentitiesListOncePerBucket() async throws {
    let bucket = FakeBucket(objects: [
      "M31/2026-10-18/l_1.fits": Data("one".utf8),
      "M31/2026-10-18/l_2.fits": Data("two two".utf8),
      "M31/2026-10-19/l_3.fits": Data("three".utf8),
    ])
    let paths = [
      "s3://astro/M31/2026-10-18/l_1.fits", "s3://astro/M31/2026-10-18/l_2.fits",
      "/c/M31/local.fits", "s3://astro/M31/2026-10-19/l_3.fits",
    ]

    let identities = await FrameStager(stores: [bucket.store]).identities(of: paths)

    #expect(identities.count == 3, "only the bucket's frames: \(identities)")
    #expect(identities["s3://astro/M31/2026-10-18/l_1.fits"] == "3|e")
    #expect(identities["s3://astro/M31/2026-10-18/l_2.fits"] == "7|e")
    #expect(identities["/c/M31/local.fits"] == nil, "a frame of this Mac has its own attributes")
    #expect(
      bucket.listed.sorted() == ["M31/2026-10-18/", "M31/2026-10-19/"],
      "one listing per folder the keys sit in — never the bucket's root")
  }

  @Test("a bucket this run cannot read answers no identity, and the digest falls back")
  func testIdentitiesWithoutAStore() async throws {
    let identities = await FrameStager().identities(of: ["s3://astro/M31/l_1.fits"])

    #expect(identities.isEmpty, "no store, nothing read — never a guessed identity")
  }

  @Test("a listing that fails leaves that bucket's frames without an identity")
  func testIdentitiesWhenTheListingFails() async throws {
    let bucket = FakeBucket(objects: ["M31/l_1.fits": Data("one".utf8)])
    bucket.failListing(true)

    let identities = await FrameStager(stores: [bucket.store]).identities(
      of: ["s3://astro/M31/l_1.fits"])

    #expect(identities.isEmpty)
  }

  @Test(
    "the prefix a run's keys share, up to the last slash",
    arguments: [
      (["M31/a/l_1.fits", "M31/a/l_2.fits"], "M31/a/"),
      (["M31/a/l_1.fits", "M31/b/l_2.fits"], "M31/"),
      (["M31/l_1.fits"], "M31/"),
      (["l_1.fits"], ""),
      (["M31/a/l.fits", "other/b/l.fits"], ""),
      ([], ""),
    ])
  func testCommonPrefix(keys: [String], prefix: String) {
    #expect(FrameStager.commonPrefix(of: keys) == prefix)
  }

  @Test("the buckets a run has no connection for, by name")
  func testMissingBuckets() async throws {
    let bucket = FakeBucket(objects: [:])
    let stager = FrameStager(stores: [bucket.store])

    #expect(stager.missingBuckets(of: ["/c/l.fits", "s3://astro/M31/l.fits"]).isEmpty)
    #expect(
      stager.missingBuckets(of: ["s3://other/M31/l.fits", "s3://third/l.fits"])
        == ["other", "third"], "named, sorted, each once")
  }

  @Test(
    "one listing per folder the keys sit in, never the whole bucket",
    arguments: [
      (["M31/a/l_1.fits", "M31/a/l_2.fits"], ["M31/a/"]),
      (["M31/l_1.fits", "calib/d_1.fits"], ["M31/", "calib/"]),
      (["l_1.fits"], [""]),
    ])
  func testFoldersOfKeys(keys: [String], folders: [String]) {
    #expect(FrameStager.folders(of: keys).sorted() == folders.sorted())
  }

  @Test("a run whose lights and calibration live apart lists both folders, not the bucket")
  func testIdentitiesListEachFolder() async throws {
    let bucket = FakeBucket(objects: [
      "M31/l_1.fits": Data("one".utf8), "calib/d_1.fits": Data("two".utf8),
    ])

    let identities = await FrameStager(stores: [bucket.store]).identities(
      of: ["s3://astro/M31/l_1.fits", "s3://astro/calib/d_1.fits"])

    #expect(identities.count == 2)
    #expect(bucket.listed.sorted() == ["M31/", "calib/"], "never the bucket's root")
  }
}
