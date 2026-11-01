import Foundation
import StackKit
import TestSupport
import Testing

/// Card 0163: every light filter says where it came from — the FITS card as written, the file
/// name, the folder, the wheel slot, `info.txt`, the signal or the user's mapping — so the import
/// row can show « Hα — FITS FILTER « H-alpha 7nm » » next to the picker (R2: overridable).
@Suite("Filter origin — where each light filter came from, carried to its set")
struct FilterOriginTests {
  struct Case: CustomTestStringConvertible, Sendable {
    let name: String
    /// File path under the scan folder, and its cards.
    let file: String
    let cards: [String: String]
    let filter: String
    let origin: FilterOrigin
    var testDescription: String { name }
  }

  static let cases: [Case] = [
    Case(
      name: "FITS FILTER, tolerant name", file: "session/light_1.fits",
      cards: InventoryBuilderTests.asi("'Light Frame'", filter: "'H-alpha 7nm'", exptime: "300.0"),
      filter: "Ha", origin: FilterOrigin(source: .header, raw: "H-alpha 7nm")),
    Case(
      name: "file name", file: "session/light_filter-OIII_001.fits",
      cards: InventoryBuilderTests.asi("'Light Frame'", exptime: "300.0"), filter: "OIII",
      origin: FilterOrigin(source: .fileName, raw: "OIII")),
    Case(
      name: "folder", file: "SII_300s/light_001.fits",
      cards: InventoryBuilderTests.asi("'Light Frame'", exptime: "300.0"), filter: "SII",
      origin: FilterOrigin(source: .folder, raw: "SII_300s")),
  ]

  @Test("testScan_FilterOrigin: header, file name, folder", .scratchDirectory, arguments: cases)
  func testScanFilterOrigin(row: Case) throws {
    let dir = try InventoryBuilderFallbackTests.folder("scan")
    let url = dir.appendingPathComponent(row.file)
    try TestFITS.write(
      url.lastPathComponent, in: url.deletingLastPathComponent(), pixel: 1200, cards: row.cards)
    let inventory = try InventoryBuilderTests.scan(dir)
    let light = try #require(inventory.frames.first { $0.type == .light })
    #expect(light.filter == row.filter)
    #expect(light.filterOrigin == row.origin)
    let set = try #require(inventory.sets.first { $0.key.type == .light })
    #expect(set.filterOrigin == row.origin)
  }

  @Test("testScan_FilterOrigin_WheelSlot: a SharpCap slot names the filter", .scratchDirectory)
  func testScanFilterOriginWheelSlot() throws {
    let dir = try InventoryBuilderFallbackTests.folder("scan")
    try InventoryBuilderWheelTests.slotFrame(
      "2021-08-13-2347_8-2-CapObj_0000.FIT", in: dir.appendingPathComponent("CapObj"), slot: 2)
    let inventory = try InventoryBuilderTests.scan(dir)
    let light = try #require(inventory.frames.first { $0.type == .light })
    #expect(light.filter == "R")
    #expect(light.filterOrigin == FilterOrigin(source: .wheelSlot, raw: "2"))
  }

  @Test("testManifest_FilterOrigin: info.txt names the folder's filter", .scratchDirectory)
  func testManifestFilterOrigin() throws {
    let root = try ScratchDirectory.url
    let folder = root.appendingPathComponent("M101old")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("LL RR\n300 gain\n-15°\n".utf8).write(to: folder.appendingPathComponent("info.txt"))
    var inventory = Inventory(
      root: root.path,
      frames: try CaptureManifestTests.unknownFrames(
        in: folder, runs: ["2021-08-14_00_10_00Z"], perRun: ["a.fit"]))
    CaptureManifest.apply(files: [folder.appendingPathComponent("info.txt").path], to: &inventory)
    #expect(inventory.frames.first?.filterOrigin == FilterOrigin(source: .manifest, raw: "L"))
  }

  @Test("testDetect_FilterOrigin: unlabeled lights named by their signal", .scratchDirectory)
  func testDetectFilterOrigin() throws {
    let dir = try InventoryBuilderFallbackTests.folder("scan")
    let levels: [UInt16] = [3000, 1100]
    var second = 0
    for (block, level) in levels.enumerated() {
      if block > 0 { second += 200 }
      for index in 0..<6 {
        try TestFITS.write(
          String(format: "img_%02d_%02d.fits", block, index), in: dir, width: 16, height: 16,
          pixel: level,
          cards: [
            "GAIN": "300", "OFFSET": "50", "CCD-TEMP": "-20.0", "XBINNING": "1", "EXPTIME": "30.0",
            "DATE-OBS": InventoryBuilderWheelTests.dateObs(second),
          ])
        second += 31
      }
    }
    let inventory = try InventoryBuilderTests.scan(dir)
    let named = inventory.frames.filter { !$0.filter.isEmpty }
    #expect(!named.isEmpty)
    #expect(named.allSatisfy { $0.filterOrigin == FilterOrigin(source: .signal, raw: "") })
  }

  @Test("testMapping_FilterOrigin: the user's mapping wins and says what it replaced")
  func testMappingFilterOrigin() {
    var inventory = ColorChoiceTests.seed(
      ["R", "B"].map { ColorChoiceTests.frame(.light, filter: $0) })
    inventory.applyFilterMapping(["B": "Ha"])
    let mapped = inventory.frames.first { $0.filter == "Ha" }
    #expect(mapped?.filterOrigin == FilterOrigin(source: .manual, raw: "B"))
  }
}
