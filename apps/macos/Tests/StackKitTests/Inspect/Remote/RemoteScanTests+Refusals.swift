import Foundation
import StackKit
import TestSupport
import Testing

/// Card 0186: a prefix the key cannot read fails the scan with the service's words (R2: never a
/// « successful » scan of zero lights), and a prefix too large to scan is refused, named.
@Suite("RemoteScan — refusals said, never an empty inventory")
struct RemoteScanRefusalTests {
  /// What the bucket answers every header read with.
  struct Denied: Error, CustomStringConvertible {
    var description: String { "S3 403 AccessDenied: Access Denied." }
  }

  /// A frame the listing names but `get` cannot read: `fatal` says whether the store reads the
  /// failure as the bucket's (every object) or the object's alone.
  static func scan(fatal: Bool) async throws -> Inventory {
    let base = try InventoryBuilderFallbackTests.folder("denied")
    try TestFITS.write(
      "lights/l_1.fits", in: base, pixel: 900,
      cards: InventoryBuilderTests.asi("'Light Frame'", filter: "'L'", exptime: "120.0"))
    let memory = try MemoryStore(tree: base, prefix: "M31/")
    let store = RemoteObjectStore(
      bucket: "astro", list: memory.store.list, get: { _, _ in throw Denied() },
      failsTheScan: { _ in fatal })
    return try await RemoteScan(store: store, prefix: "M31", timeZone: RemoteScanTests.zone)
      .inventory()
  }

  @Test("a header the bucket refuses fails the scan, in the service's words", .scratchDirectory)
  func testHeaderTheBucketRefusesFailsTheScan() async throws {
    await #expect {
      _ = try await Self.scan(fatal: true)
    } throws: { error in
      guard case InspectError.remoteUnreadable(let path, let reason) = error else { return false }
      return path == "s3://astro/M31/lights/l_1.fits"
        && reason == "S3 403 AccessDenied: Access Denied."
    }
  }

  @Test(
    "one frame refused among readable ones stays that frame's skip (an archived frame)",
    .scratchDirectory)
  func testOneRefusedFrameAmongReadable() async throws {
    let base = try InventoryBuilderFallbackTests.folder("archived")
    for name in ["l_1", "l_2"] {
      try TestFITS.write(
        "lights/\(name).fits", in: base, pixel: 900,
        cards: InventoryBuilderTests.asi("'Light Frame'", filter: "'L'", exptime: "120.0"))
    }
    let memory = try MemoryStore(tree: base, prefix: "M31/")
    let store = RemoteObjectStore(
      bucket: "astro", list: memory.store.list,
      get: { key, range in
        if key.hasSuffix("l_2.fits") { throw Denied() }
        return try await memory.store.get(key, range)
      },
      failsTheScan: { _ in true })

    let inventory = try await RemoteScan(
      store: store, prefix: "M31", timeZone: RemoteScanTests.zone
    ).inventory()

    #expect(inventory.frames.map(\.path) == ["s3://astro/M31/lights/l_1.fits"])
    #expect(inventory.warnings.contains { $0.contains("l_2.fits") }, "\(inventory.warnings)")
  }

  @Test(
    "a header the object alone fails (gone since the listing) stays the frame's skip",
    .scratchDirectory)
  func testHeaderTheObjectFailsIsASkip() async throws {
    let inventory = try await Self.scan(fatal: false)

    #expect(inventory.frames.isEmpty)
    #expect(inventory.warnings.contains { $0.contains("l_1.fits") }, "\(inventory.warnings)")
  }

  @Test(
    "a prefix holding more objects than a scan reads is refused before any read",
    arguments: [(RemoteSnapshot.maxObjects, false), (RemoteSnapshot.maxObjects + 1, true)])
  func testListingBeyondTheCapIsRefused(count: Int, refused: Bool) async throws {
    let objects = (0..<count).map {
      RemoteObjectStore.Object(key: "M31/f_\($0).fits", size: 1, etag: "e")
    }
    let store = RemoteObjectStore(
      bucket: "astro", list: { _ in objects }, get: { _, _ in Data() })

    do {
      _ = try await RemoteSnapshot.load(store: store, prefix: "M31")
      #expect(!refused, "\(count) objects scanned")
    } catch InspectError.remoteTooLarge(let path, let limit) {
      #expect(refused)
      #expect(path == "s3://astro/M31" && limit == RemoteSnapshot.maxObjects)
    }
  }

  @Test("sidecars never count toward the cap: only the frames a scan reads")
  func testSidecarsDoNotCount() async throws {
    let objects = (0..<RemoteSnapshot.maxObjects).flatMap { index in
      ["M31/f_\(index).fits", "M31/f_\(index).fits.txt"].map {
        RemoteObjectStore.Object(key: $0, size: 1, etag: "e")
      }
    }
    // Every frame and sidecar read fails as the object's: the cap is the only refusal possible.
    let store = RemoteObjectStore(
      bucket: "astro", list: { _ in objects },
      get: { _, _ in throw CocoaError(.fileNoSuchFile) })

    let snapshot = try await RemoteSnapshot.load(store: store, prefix: "M31")

    #expect(snapshot.listing.files.count == 2 * RemoteSnapshot.maxObjects)
  }

  @Test("an output/ folder the walk skips never counts toward the cap")
  func testOutputFolderDoesNotCount() async throws {
    let objects =
      (0...RemoteSnapshot.maxObjects).map {
        RemoteObjectStore.Object(key: "M31/output/run/f_\($0).fits", size: 1, etag: "e")
      } + [RemoteObjectStore.Object(key: "M31/notes.txt", size: 1, etag: "e")]
    let store = RemoteObjectStore(
      bucket: "astro", list: { _ in objects }, get: { _, _ in Data() })

    let snapshot = try await RemoteSnapshot.load(store: store, prefix: "M31")

    #expect(snapshot.listing.files == ["s3://astro/M31/notes.txt"])
  }
}
