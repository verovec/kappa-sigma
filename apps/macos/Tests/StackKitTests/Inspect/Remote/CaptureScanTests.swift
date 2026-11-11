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
}
