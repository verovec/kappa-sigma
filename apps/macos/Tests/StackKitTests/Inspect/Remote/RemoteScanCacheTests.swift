import Foundation
import ProjectKit
import StackKit
import Synchronization
import TestSupport
import Testing

/// Card 0168: a second scan of the same prefix reads no header and no side file it already has,
/// reads the one key whose ETag changed, and forgets the keys the bucket no longer holds.
@Suite("RemoteScan — a rescan reads only what changed")
struct RemoteScanCacheTests {
  static let zone = TimeZone(identifier: "Europe/Paris") ?? .gmt

  /// One read of the bucket.
  struct Read: Sendable, Equatable {
    let key: String
    let range: ClosedRange<Int64>?

    /// A header is read from the first byte; a side file whole; a centred run from inside the
    /// data unit, past the header's 2880-byte blocks.
    var isHeaderOrSideFile: Bool { (range?.lowerBound ?? 0) == 0 }
  }

  /// A bucket whose objects a test replaces or removes between scans, every read logged.
  final class ChangingStore: Sendable {
    let bucket = "astro"
    private let state = Mutex<(objects: [String: (data: Data, etag: String)], reads: [Read])>(
      ([:], []))

    /// The files under `root` as keys `prefix` + their relative path, each tagged by its bytes.
    init(tree root: URL, prefix: String) throws {
      var objects: [String: (Data, String)] = [:]
      let base = root.standardizedFileURL.path
      let walker = FileManager.default.enumerator(
        at: root, includingPropertiesForKeys: [.isRegularFileKey])
      while let url = walker?.nextObject() as? URL {
        guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
          continue
        }
        let data = try Data(contentsOf: url)
        let key = prefix + String(url.standardizedFileURL.path.dropFirst(base.count + 1))
        objects[key] = (data, Self.etag(data))
      }
      state.withLock { $0.objects = objects }
    }

    /// An ETag that follows the bytes, as a bucket's does.
    static func etag(_ data: Data) -> String { "etag-\(data.count)-\(data.hashValue)" }

    /// Every read since the last `forgetReads()`, in order.
    var reads: [Read] { state.withLock { $0.reads } }

    /// The reads that fetched a header or a side file — what a cache spares.
    var headerAndSideReads: [Read] { reads.filter(\.isHeaderOrSideFile) }

    func forgetReads() { state.withLock { $0.reads = [] } }

    /// Replaces `key`'s bytes, which gives it a new ETag.
    func replace(_ key: String, with data: Data) {
      state.withLock { $0.objects[key] = (data, Self.etag(data)) }
    }

    /// Takes `key` out of the bucket.
    func remove(_ key: String) { state.withLock { $0.objects[key] = nil } }

    var store: RemoteObjectStore {
      RemoteObjectStore(
        bucket: bucket,
        list: { prefix in
          self.state.withLock { $0.objects }
            .filter { $0.key.hasPrefix(prefix) }
            .sorted { $0.key < $1.key }
            .map {
              RemoteObjectStore.Object(
                key: $0.key, size: Int64($0.value.data.count), etag: $0.value.etag)
            }
        },
        get: { key, range in
          let object = self.state.withLock { state -> (data: Data, etag: String)? in
            state.reads.append(Read(key: key, range: range))
            return state.objects[key]
          }
          guard let data = object?.data else { throw CocoaError(.fileNoSuchFile) }
          guard let range else { return data }
          let upper = min(Int(range.upperBound), data.count - 1)
          guard upper >= Int(range.lowerBound) else { return Data() }
          return data.subdata(in: Int(range.lowerBound)..<(upper + 1))
        })
    }
  }

  /// A prefix holding two frames typed by their curve (each needs one centred run), a light with
  /// its sidecar, and a preview nothing reads.
  static func tree(_ name: String) throws -> URL {
    let base = try InventoryBuilderFallbackTests.folder(name)
    try TestFITS.write("session/a_flat.fits", in: base, pixel: 30000, cards: ["EXPTIME": "2.0"])
    try TestFITS.write("session/b_zero.fits", in: base, pixel: 300, cards: ["EXPTIME": "0.0"])
    try TestFITS.write(
      "lights/l_1.fits", in: base, pixel: 900,
      cards: InventoryBuilderTests.asi("'Light Frame'", filter: "'L'", exptime: "120.0"))
    try Data("Gain = 250\n".utf8).write(to: base.appendingPathComponent("lights/l_1.fits.txt"))
    return base
  }

  @Test(
    "testRescanReadsOnlyChangedKeys: a cached header is not read again, a changed ETag is",
    .scratchDirectory)
  func testRescanReadsOnlyChangedKeys() async throws {
    let base = try Self.tree("rescan")
    let bucket = try ChangingStore(tree: base, prefix: "nights/x/")
    let scan = RemoteScan(store: bucket.store, prefix: "nights/x", timeZone: Self.zone)

    let first = try await scan.scan()
    #expect(!first.cache.entries.isEmpty && !bucket.headerAndSideReads.isEmpty)

    bucket.forgetReads()
    let second = try await scan.scan(cache: first.cache)

    #expect(
      bucket.headerAndSideReads.isEmpty,
      "every ETag unchanged: no header and no side file is fetched a second time")
    #expect(
      InventoryJSON.differences(
        recorded: InventoryJSON.object(first.inventory) { $0 },
        actual: InventoryJSON.object(second.inventory) { $0 }
      ).isEmpty, "the cached scan answers exactly what the first one did")

    let changed = "nights/x/lights/l_1.fits"
    let other = try TestFITS.write(
      "lights/l_2.fits", in: base, pixel: 1200,
      cards: InventoryBuilderTests.asi("'Light Frame'", filter: "'L'", exptime: "120.0"))
    bucket.replace(changed, with: try Data(contentsOf: other))
    bucket.forgetReads()
    let third = try await scan.scan(cache: second.cache)

    #expect(
      bucket.headerAndSideReads.map(\.key) == [changed],
      "one ETag changed: that key alone is read, its unchanged sidecar is not")
    #expect(third.inventory.frames.count == first.inventory.frames.count)

    bucket.remove("nights/x/session/a_flat.fits")
    bucket.forgetReads()
    let fourth = try await scan.scan(cache: third.cache)

    #expect(
      !fourth.inventory.frames.contains { $0.path.hasSuffix("a_flat.fits") },
      "a key the bucket no longer holds leaves the inventory")
    #expect(
      !fourth.cache.entries.keys.contains("nights/x/session/a_flat.fits"),
      "and the cache forgets it, instead of growing for ever")
    #expect(bucket.headerAndSideReads.isEmpty, "the keys that stayed are still not read")
  }

  @Test(
    "the centred pixel runs are read again, never cached: a body stays a few KB per frame",
    .scratchDirectory)
  func testPixelRunsAreNotCached() async throws {
    let base = try Self.tree("runs")
    let bucket = try ChangingStore(tree: base, prefix: "")
    let scan = RemoteScan(store: bucket.store, prefix: "", timeZone: Self.zone)

    let first = try await scan.scan()
    bucket.forgetReads()
    _ = try await scan.scan(cache: first.cache)

    let again = bucket.reads.filter { !$0.isHeaderOrSideFile }
    #expect(!again.isEmpty, "a run the scan asks for is fetched by range, as the first scan did")
    let body = try first.cache.json()
    #expect(
      body.count < 8 * 1024,
      "no 200 000-value run in the body: \(body.count) bytes for \(first.cache.entries.count) keys")
  }

  @Test("the cache travels as JSON and a foreign body is refused, never crashes", .scratchDirectory)
  func testCacheJSONRoundTrip() async throws {
    let base = try Self.tree("json")
    let bucket = try ChangingStore(tree: base, prefix: "")
    let scan = RemoteScan(store: bucket.store, prefix: "", timeZone: Self.zone)

    let first = try await scan.scan()
    let json = try first.cache.json()
    let loaded = try RemoteScanCache(json: json)

    #expect(loaded == first.cache)
    bucket.forgetReads()
    _ = try await scan.scan(cache: loaded)
    #expect(
      bucket.headerAndSideReads.isEmpty,
      "a cache read back from the database spares the same reads")
    #expect(throws: (any Error).self) { try RemoteScanCache(json: Data("not json".utf8)) }
  }

  @Test("a key the scan never reads is not carried from one cache to the next", .scratchDirectory)
  func testOnlyWalkedFilesAreCached() async throws {
    let base = try Self.tree("skipped")
    try FileManager.default.createDirectory(
      at: base.appendingPathComponent("output"), withIntermediateDirectories: true)
    try TestFITS.write("output/old_master.fits", in: base, pixel: 500, cards: ["EXPTIME": "1.0"])
    try Data(repeating: 1, count: 64).write(to: base.appendingPathComponent("lights/thumb.jpg"))
    let bucket = try ChangingStore(tree: base, prefix: "")

    let scanned = try await RemoteScan(store: bucket.store, prefix: "", timeZone: Self.zone).scan()

    #expect(!scanned.cache.entries.keys.contains { $0.hasPrefix("output/") }, "output/ is skipped")
    #expect(!scanned.cache.entries.keys.contains("lights/thumb.jpg"), "nothing was read of it")
    #expect(scanned.cache.entries.keys.contains("lights/l_1.fits.txt"), "the sidecar was read")
  }

  @Test("the stored path of a remote source is the root its scan walks", .scratchDirectory)
  func testSourcePathIsTheScanRoot() async throws {
    let base = try Self.tree("root")
    let bucket = try ChangingStore(tree: base, prefix: "nights/M31/")

    let snapshot = try await RemoteSnapshot.load(store: bucket.store, prefix: "nights/M31/")

    #expect(snapshot.root == ProjectSource.remotePath(bucket: "astro", prefix: "nights/M31"))
    let whole = try await RemoteSnapshot.load(store: bucket.store, prefix: "")
    #expect(whole.root == ProjectSource.remotePath(bucket: "astro", prefix: ""))
  }

  @Test(
    "a side file bigger than a sidecar is read again, never carried in the body",
    .scratchDirectory)
  func testOversizeSideFileIsNotCached() async throws {
    let base = try Self.tree("sidecar")
    let big = String(repeating: "Gain = 250\n", count: 20_000)
    #expect(big.utf8.count > RemoteScanCache.maxCachedSideFileBytes)
    try Data(big.utf8).write(to: base.appendingPathComponent("lights/l_1.fits.txt"))
    let bucket = try ChangingStore(tree: base, prefix: "")
    let scan = RemoteScan(store: bucket.store, prefix: "", timeZone: Self.zone)

    let first = try await scan.scan()
    #expect(first.cache.entries["lights/l_1.fits.txt"]?.contents == nil, "too big to keep")
    #expect(first.cache.entries["lights/l_1.fits"]?.header != nil, "its frame's header is kept")

    bucket.forgetReads()
    _ = try await scan.scan(cache: first.cache)

    #expect(
      bucket.reads.contains { $0.key == "lights/l_1.fits.txt" },
      "so it is fetched again, as the scan needs it")
    #expect(
      !bucket.reads.contains { $0.key == "lights/l_1.fits" && $0.isHeaderOrSideFile },
      "while the cached header is not")
  }

  @Test("testIdentitiesNameEachKeyAsARunDoes: the scan's listing, by virtual path")
  func testIdentitiesNameEachKeyAsARunDoes() {
    let cache = RemoteScanCache(entries: [
      "M31/l_1.fits": .init(etag: "abc", size: 2880), "M31/info.txt": .init(etag: "d", size: 12),
    ])

    #expect(
      cache.identities(bucket: "astro") == [
        "s3://astro/M31/l_1.fits": RemoteObjectStore.Object.identity(size: 2880, etag: "abc"),
        "s3://astro/M31/info.txt": RemoteObjectStore.Object.identity(size: 12, etag: "d"),
      ])
    #expect(RemoteObjectStore.Object.identity(size: 2880, etag: "abc") == "2880|abc")
  }

  @Test(
    "testScanIdentitiesNameEveryFrameOfItsInventory: the sheet can prove every set it scanned",
    .scratchDirectory)
  func testScanIdentitiesNameEveryFrameOfItsInventory() async throws {
    let bucket = try ChangingStore(tree: Self.tree("identities"), prefix: "nights/M31/")

    let scanned = try await RemoteScan(
      store: bucket.store, prefix: "nights/M31/", timeZone: Self.zone
    ).scan()

    let identities = scanned.cache.identities(bucket: bucket.bucket)
    let paths = scanned.inventory.sets.flatMap { $0.frames.map(\.path) }
    #expect(!paths.isEmpty)
    #expect(
      paths.allSatisfy { identities[$0] != nil },
      "every frame a set holds is named as the run lists it: \(paths) vs \(identities.keys)")
  }
}
