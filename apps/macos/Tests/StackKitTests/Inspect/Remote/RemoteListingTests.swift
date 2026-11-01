import Foundation
import StackKit
import Synchronization
import TestSupport
import Testing

/// Card 0167: a key space walks like a folder — byte order per folder, hidden and `output` folders
/// skipped, packages listed as skipped — and a remote path's scheme and bucket are no folder names.
@Suite("InspectWalk over keys — an S3 prefix listed like the disk")
struct RemoteListingTests {
  @Test("testSkipsLikeLocal: the same tree on disk and as keys lists the same", .scratchDirectory)
  func testSkipsLikeLocal() throws {
    let dir = try InventoryBuilderFallbackTests.folder("walk")
    let light = InventoryBuilderTests.asi("'Light Frame'", filter: "'L'", exptime: "120.0")
    for relative in [
      "lights/l_1.fits", "lights.fits", "lights/sub/l_2.fits", "output/stack.fits", "Output/s.fits",
      ".hidden/x.fits", "old.astrostack/stacks/1/c.fits", "Viewer.app/Contents/x.fits", ".dot.fits",
      "a-b/c.fits", "a/b.fits", "a.fits",
    ] {
      try TestFITS.write(relative, in: dir, pixel: 900, cards: light)
    }
    let local = try FrameSource.files.listing(under: dir.path, skippingOutput: true)
    let keys = try MemoryStore(tree: dir, prefix: "").objects.keys.sorted()

    let remote = InspectWalk.listing(keys: keys, under: "s3://astro/p", skippingOutput: true)

    let relative = { (paths: [String], root: String) in
      paths.map { InspectWalk.relative($0, to: root) }
    }
    #expect(relative(remote.files, "s3://astro/p") == relative(local.files, dir.path))
    #expect(relative(remote.packages, "s3://astro/p") == relative(local.packages, dir.path))
  }

  @Test("a folder marker key is no file")
  func testFolderMarkerIgnored() {
    let listing = InspectWalk.listing(
      keys: ["night/", "night/l.fits"], under: "s3://astro", skippingOutput: true)
    #expect(listing.files == ["s3://astro/night/l.fits"])
  }

  @Test(
    "testS3SchemeAndBucketNotTokens: a bucket named darks types nothing",
    arguments: [
      ("s3://darks/M31/lights/x.fits", FrameType.light), ("s3://darks/M31/x.fits", .unknown),
      ("s3://flats/x.fits", .unknown),
    ])
  func testS3SchemeAndBucketNotTokens(path: String, expected: FrameType) {
    #expect(PathMeta.typeFromFolders(path) == expected)
  }
}

/// Card 0167: which frames a remote scan names « non vérifié (distant) » — the span of the
/// decision each missed read belonged to — and a cancelled scan stops, never degrades.
@Suite("RemoteScan.unchecked and cancellation")
struct RemoteUncheckedTests {
  static func frame(_ name: String, _ type: FrameType, instrument: String) -> CaptureFrame {
    var frame = CaptureFrame(path: "s3://astro/" + name)
    frame.type = type
    frame.instrument = instrument
    // Camera B shoots another exposure: its sets are its own.
    frame.exposureMs = type == .bias ? 0 : instrument == "B" ? 120_000 : 60_000
    return frame
  }

  static var inventory: Inventory {
    var inventory = Inventory(
      root: "s3://astro",
      frames: [
        frame("a/l1.fits", .light, instrument: "A"), frame("a/l2.fits", .light, instrument: "A"),
        frame("a/b1.fits", .bias, instrument: "A"), frame("a/f1.fits", .flat, instrument: "A"),
        frame("b/l1.fits", .light, instrument: "B"), frame("b/d1.fits", .dark, instrument: "B"),
      ])
    inventory.regroup()
    return inventory
  }

  @Test("a pedestal read names every light, not the flats and darks")
  func testPedestalNamesLights() {
    let named = RemoteScan.unchecked(
      ["s3://astro/a/b1.fits"], planes: ["s3://astro/a/b1.fits"], in: Self.inventory)
    #expect(named.contains("s3://astro/a/l1.fits") && named.contains("s3://astro/b/l1.fits"))
    #expect(!named.contains("s3://astro/a/f1.fits") && !named.contains("s3://astro/b/d1.fits"))
  }

  @Test("a light's CFA probe names its instrument's frames, not another camera's")
  func testCFAProbeNamesInstrument() {
    let named = RemoteScan.unchecked(
      ["s3://astro/a/l1.fits"], planes: ["s3://astro/a/l1.fits"], in: Self.inventory)
    #expect(
      Set(["a/l1.fits", "a/l2.fits", "a/b1.fits", "a/f1.fits"].map { "s3://astro/" + $0 })
        .isSubset(of: Set(named)))
    #expect(!named.contains("s3://astro/b/l1.fits") && !named.contains("s3://astro/b/d1.fits"))
  }

  @Test("a missed centred run names its frame's set only")
  func testMissedRunNamesItsSet() {
    let named = RemoteScan.unchecked(["s3://astro/b/d1.fits"], planes: [], in: Self.inventory)
    #expect(named == ["s3://astro/b/d1.fits"])
  }

  @Test("a scan cancelled while reading throws, it does not degrade")
  func testCancelledScanThrows() async throws {
    let started = Mutex(false)
    // Never yields nor finishes (its continuation is kept): iterating it suspends until cancelled.
    let (pending, keep) = AsyncStream<Void>.makeStream()
    let store = RemoteObjectStore(
      bucket: "astro",
      list: { _ in [.init(key: "n/l.fits", size: 100_000, etag: "e")] },
      get: { _, _ in
        started.withLock { $0 = true }
        for await _ in pending {}
        try Task.checkCancellation()
        return Data()
      })
    let task = Task { try await RemoteScan(store: store, prefix: "n").inventory() }
    while !started.withLock({ $0 }) { await Task.yield() }

    task.cancel()

    await #expect(throws: CancellationError.self) { try await task.value }
    keep.finish()
  }
}
