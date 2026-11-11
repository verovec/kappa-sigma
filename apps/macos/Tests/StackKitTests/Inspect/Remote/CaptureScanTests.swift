import Foundation
import StackKit
import TestSupport
import Testing

/// Card 0190: folders of this Mac and bucket prefixes scan as one capture — the inventory the
/// same folders give from disk, so the calibration under one root serves the lights of another.
@Suite("CaptureScan — folders and bucket prefixes scanned as one capture")
struct CaptureScanTests {
  static let zone = RemoteScanTests.zone

  /// A capture in two folders: `lights/` (3 mono lights) and `calib/` (darks and bias).
  static func tree() throws -> URL {
    let base = try InventoryBuilderFallbackTests.folder("mixed")
    let cards = { (type: String, exposure: String) in
      [
        "IMAGETYP": type, "EXPTIME": exposure, "GAIN": "100", "CCD-TEMP": "-10.0",
        "OBJECT": "'M42'", "FILTER": "'L'", "DATE-OBS": "'2026-09-15T03:00:00'",
      ]
    }
    for index in 0..<3 {
      try TestFITS.write(
        "lights/l_\(index).fits", in: base, pixel: 1200, cards: cards("'Light Frame'", "15.0"))
      try TestFITS.write(
        "calib/DARK/d_\(index).fits", in: base, pixel: 400, cards: cards("'Dark Frame'", "15.0"))
      try TestFITS.write(
        "calib/BIAS/b_\(index).fits", in: base, pixel: 300, cards: cards("'Bias Frame'", "0.0"))
    }
    return base
  }

  /// What sets one root apart from another once its paths are spelled as on disk.
  enum Where: String, CaseIterable, Sendable {
    case disk, bucket
  }

  /// `inventory` as JSON without its display root (two roots on different stores share none).
  static func object(_ inventory: Inventory, _ spell: (String) -> String) -> InventoryJSON.Object {
    var out = InventoryJSON.object(inventory, normalize: spell)
    out["root"] = ""
    return out
  }

  @Test(
    "lights and calibration scan the same wherever each is read from", .scratchDirectory,
    arguments: [
      (Where.disk, Where.bucket), (Where.bucket, Where.disk), (Where.bucket, Where.bucket),
    ])
  func testScan_MixedRoots_EqualsLocal(lights: Where, calib: Where) async throws {
    let base = try Self.tree()
    let folders = ["lights": lights, "calib": calib]
    let local = try InventoryBuilder(timeZone: Self.zone).scan(
      paths: ["lights", "calib"].map { base.appendingPathComponent($0).path })
    let memory = try MemoryStore(tree: base, prefix: "night/")
    let roots = ["lights", "calib"].map { name -> CaptureScan.Root in
      folders[name] == .disk
        ? .folder(base.appendingPathComponent(name).path)
        : .prefix(.init(store: memory.store, prefix: "night/" + name))
    }

    let scanned = try await CaptureScan(roots: roots, timeZone: Self.zone).scan()

    let differences = InventoryJSON.differences(
      recorded: Self.object(local) { $0 },
      actual: Self.object(scanned.inventory) {
        $0.replacingOccurrences(of: "s3://astro/night", with: base.path)
      })
    #expect(differences.isEmpty, "\(differences.joined(separator: "\n"))")
    #expect(scanned.inventory.frames.count == 9)
    let remote = folders.filter { $0.value == .bucket }.map { "s3://astro/night/" + $0.key }
    #expect(Set(scanned.caches.keys) == Set(remote), "one cache per prefix, by its root")
    #expect(scanned.caches.values.allSatisfy { !$0.entries.isEmpty }, "what each scan read")
    for name in folders.filter({ $0.value == .disk }).keys {
      #expect(memory.gets.allSatisfy { !$0.key.hasPrefix("night/\(name)/") }, "disk is not S3")
    }
  }

  @Test(
    "a prefix that cannot be listed fails the scan: never the other roots alone",
    .scratchDirectory)
  func testScan_PrefixRefused_FailsWhole() async throws {
    let base = try Self.tree()
    let refused = RemoteObjectStore(
      bucket: "astro", list: { _ in throw RemoteScanRefusalTests.Denied() },
      get: { _, _ in Data() })

    await #expect(throws: RemoteScanRefusalTests.Denied.self) {
      _ = try await CaptureScan(
        roots: [
          .folder(base.appendingPathComponent("lights").path),
          .prefix(.init(store: refused, prefix: "night/calib")),
        ], timeZone: Self.zone
      ).scan()
    }
  }

  @Test(
    "a prefix inside another prefix of the capture is walked once: no frame counted twice",
    .scratchDirectory)
  func testScan_NestedPrefixes_NoDuplicate() async throws {
    let base = try Self.tree()
    let memory = try MemoryStore(tree: base, prefix: "night/")
    let outer = try await CaptureScan(
      roots: [.prefix(.init(store: memory.store, prefix: "night"))], timeZone: Self.zone
    ).scan()

    let nested = try await CaptureScan(
      roots: [
        .prefix(.init(store: memory.store, prefix: "night/calib")),
        .prefix(.init(store: memory.store, prefix: "night")),
        .prefix(.init(store: memory.store, prefix: "night/")),
      ], timeZone: Self.zone
    ).scan()

    #expect(nested.inventory.frames.count == 9)
    #expect(
      nested.inventory.frames.map(\.path).sorted() == outer.inventory.frames.map(\.path).sorted())
    #expect(Array(nested.caches.keys) == ["s3://astro/night"], "the covering prefix alone is read")
  }

  @Test(
    "a bucket frame typed by its pixels takes a second pass: the folders scan the same",
    .scratchDirectory)
  func testScan_SecondPass_KeepsTheDiskReads() async throws {
    let base = try Self.tree()
    try TestFITS.write("calib/x/a_flat.fits", in: base, pixel: 30000, cards: ["EXPTIME": "2.0"])
    try TestFITS.write("calib/x/b_zero.fits", in: base, pixel: 300, cards: ["EXPTIME": "0.0"])
    let folders = ["lights", "calib"].map { base.appendingPathComponent($0).path }
    let local = try InventoryBuilder(timeZone: Self.zone).scan(paths: folders)
    let memory = try MemoryStore(tree: base, prefix: "night/")

    let scanned = try await CaptureScan(
      roots: [.folder(folders[0]), .prefix(.init(store: memory.store, prefix: "night/calib"))],
      timeZone: Self.zone
    ).scan()

    let differences = InventoryJSON.differences(
      recorded: Self.object(local) { $0 },
      actual: Self.object(scanned.inventory) {
        $0.replacingOccurrences(of: "s3://astro/night", with: base.path)
      })
    #expect(differences.isEmpty, "\(differences.joined(separator: "\n"))")
    #expect(scanned.inventory.frames.count { $0.classSource == .heuristic } == 2)
    #expect(
      memory.gets.contains {
        $0.key == "night/calib/x/a_flat.fits" && ($0.range?.lowerBound ?? 0) > 0
      },
      "its centred run was fetched: a second pass ran")
  }

  @Test(
    "which prefixes a capture reads: one inside another and a repeat are covered",
    arguments: [
      (["s3://a/M31", "s3://a/M31/n1", nil, "s3://a/M31"], [1, 3]),
      (["s3://a/M31/n1", "s3://a/M31/n2", "s3://b/M31"], []),
      (["s3://a/M3", "s3://a/M31"], []),
      ([nil, nil], []),
    ] as [([String?], [Int])])
  func testCovered(prefixes: [String?], covered: [Int]) {
    #expect(CaptureScan.covered(prefixes) == Set(covered))
  }
}
