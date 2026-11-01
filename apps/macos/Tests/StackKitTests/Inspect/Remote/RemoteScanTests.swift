import Foundation
import ImageKit
import StackKit
import TestSupport
import Testing

/// Card 0167: an S3 prefix scans to the inventory of the same tree on disk — the listing walked
/// like a folder, headers read by ranges, centred pixel runs fetched once — and a check that needs
/// a frame's planes is not run but named (« non vérifié (distant) »).
@Suite("RemoteScan — an S3 prefix scanned like a folder, whole frames never downloaded")
struct RemoteScanTests {
  static let zone = TimeZone(identifier: "Europe/Paris") ?? .gmt

  /// The local and the remote inventory of `root` (uploaded under `nights/x/`), the remote one's
  /// paths spelled back as local ones for the comparison.
  /// A tree scanned from disk and from the bucket.
  struct Scanned {
    let local: Inventory
    let remote: Inventory
    let store: MemoryStore
    let differences: [String]
  }

  static func both(_ root: URL, zone: TimeZone = zone) async throws -> Scanned {
    let local = try InventoryBuilder(timeZone: zone).scan(paths: [root.path])
    let memory = try MemoryStore(tree: root, prefix: "nights/x/")
    let remote = try await RemoteScan(store: memory.store, prefix: "nights/x", timeZone: zone)
      .inventory()
    let virtual = "s3://astro/nights/x"
    let differences = InventoryJSON.differences(
      recorded: InventoryJSON.object(local) { $0 },
      actual: InventoryJSON.object(remote) { $0.replacingOccurrences(of: virtual, with: root.path) }
    )
    return Scanned(local: local, remote: remote, store: memory, differences: differences)
  }

  @Test(
    "testRemoteEqualsLocal: the oracle trees scan the same from S3", .scratchDirectory,
    arguments: ["golden-single-night", "golden-two-night"])
  func testRemoteEqualsLocal(name: String) async throws {
    let oracle = try OracleFixtureTests.committedCase(name)
    let zone = try TimeZone(identifier: oracle.manifest.timezone).unwrapped("timezone")
    let input = try InventoryBuilderFallbackTests.folder("scan").appendingPathComponent("in")
    try HeaderFixture.load(name).materialize(under: input)

    let result = try await Self.both(input, zone: zone)

    #expect(result.differences.isEmpty, "\(result.differences.joined(separator: "\n"))")
    #expect(!result.remote.frames.isEmpty)
    #expect(result.remote.frames.allSatisfy { $0.path.hasPrefix("s3://astro/nights/x/") })
  }

  @Test(
    "sidecars and info.txt come from the bucket; a frame typed by its curve needs one range",
    .scratchDirectory)
  func testCenterSampleSingleRange() async throws {
    let base = try InventoryBuilderFallbackTests.folder("captures")
    let capObj = base.appendingPathComponent("M33/CapObj")
    try FileManager.default.createDirectory(at: capObj, withIntermediateDirectories: true)
    try Data("L R G B Ha\nL L\n300 gain\n-15°\n".utf8).write(
      to: capObj.appendingPathComponent("info.txt"))
    for (index, slot) in [1, 2, 3].enumerated() {
      try InventoryBuilderWheelTests.slotFrame(
        "2021-08-14-0\(index)00_6-\(slot)-CapObj_0000.FIT",
        in: capObj.appendingPathComponent("2021-08-14_0\(index)_00_00Z"), slot: slot)
    }
    try TestFITS.write("session/a_flat.fits", in: base, pixel: 30000, cards: ["EXPTIME": "2.0"])
    try TestFITS.write("session/b_zero.fits", in: base, pixel: 300, cards: ["EXPTIME": "0.0"])

    let result = try await Self.both(base)

    #expect(result.differences.isEmpty, "\(result.differences.joined(separator: "\n"))")
    #expect(result.remote.frames.filter { $0.classSource == .wheel }.count == 3)
    #expect(result.remote.frames.filter { $0.classSource == .heuristic }.count == 2)
    for name in ["session/a_flat.fits", "session/b_zero.fits"] {
      let reads = result.store.gets.filter { $0.key == "nights/x/" + name }
      #expect(reads.count == 2, "one header read, one centred run: \(reads.map(\.range))")
    }
  }

  @Test(
    "whole-frame checks are not run on a bucket: their frames are named, never downloaded",
    .scratchDirectory)
  func testPixelChecksNotChecked() async throws {
    let base = try InventoryBuilderFallbackTests.folder("osc")
    let cards = { (type: String) in
      [
        "IMAGETYP": type, "BAYERPAT": "'RGGB'", "EXPTIME": "60.0", "GAIN": "100",
        "CCD-TEMP": "-10.0", "OBJECT": "'M31'", "DATE-OBS": "'2026-10-18T21:00:00'",
      ]
    }
    for index in 0..<3 {
      try TestFITS.write(
        "lights/l_\(index).fits", in: base, pixel: 1200, cards: cards("'Light Frame'"))
      try TestFITS.write("bias/b_\(index).fits", in: base, pixel: 500, cards: cards("'Bias Frame'"))
    }

    let result = try await Self.both(base)

    #expect(result.local.notCheckedRemotely.isEmpty)
    let named = result.remote.notCheckedRemotely
    #expect(!named.isEmpty, "the OSC checks asked for planes")
    #expect(Set(named).isSubset(of: Set(result.remote.frames.map(\.path))))
    let byKey = Dictionary(grouping: result.store.gets, by: \.key)
    #expect(byKey.values.allSatisfy { $0.count <= 2 }, "header + at most one centred run per frame")
  }

  @Test("a header longer than the first read grows by ranges until END", .scratchDirectory)
  func testHeaderExtendsUntilEND() async throws {
    let base = try InventoryBuilderFallbackTests.folder("long")
    var cards = ["IMAGETYP": "'Light Frame'", "EXPTIME": "60.0", "OBJECT": "'M31'"]
    for index in 0..<900 { cards["HIST\(index)"] = "'note \(index)'" }
    let url = try TestFITS.write(
      "l.fits", in: base, width: 64, height: 64, pixel: 900, cards: cards)
    let local = try FITSFile.read(at: url).header

    let memory = try MemoryStore(tree: base, prefix: "")
    let snapshot = try await RemoteSnapshot.load(store: memory.store, prefix: "")

    #expect(try snapshot.source.header("s3://astro/l.fits") == local)
    let reads = memory.gets.filter { $0.key == "l.fits" }.compactMap(\.range)
    #expect(reads.count == 2 && reads[0].lowerBound == 0 && reads[1].lowerBound == 64 << 10)
  }
}
