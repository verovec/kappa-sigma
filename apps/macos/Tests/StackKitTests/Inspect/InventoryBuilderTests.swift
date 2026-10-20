import Foundation
import StackKit
import TestSupport
import Testing

/// Translated from the scan-level tests of `internal/inspect`: `inspect_test.go`,
/// `scanmany_test.go`, `dualband_test.go`.
@Suite("InventoryBuilder.scan — folders of FITS frames into an inventory")
struct InventoryBuilderTests {
  static let builder = InventoryBuilder(timeZone: TimeZone(identifier: "Europe/Paris") ?? .gmt)

  static func scan(_ dir: URL) throws -> Inventory { try builder.scan(paths: [dir.path]) }

  static func asi(_ type: String, filter: String = "", exptime: String = "") -> [String: String] {
    var cards = [
      "GAIN": "139", "OFFSET": "21", "CCD-TEMP": "-15.0", "XBINNING": "1",
      "INSTRUME": "'ZWO ASI1600MM Pro'", "OBJECT": "'M31'",
    ]
    if !type.isEmpty { cards["IMAGETYP"] = type }
    if !filter.isEmpty { cards["FILTER"] = filter }
    if !exptime.isEmpty { cards["EXPTIME"] = exptime }
    return cards
  }

  @Test("types, filters and sets of a classic folder; two Ha lights are one set", .scratchDirectory)
  func testInventoryBuilder_classifiesAndGroups() throws {
    let dir = try ScratchDirectory.url
    try TestFITS.write("ha_1.fits", in: dir, pixel: 1200, cards: Self.asi("'Light Frame'", filter: "'Ha'", exptime: "300.0"))
    try TestFITS.write("ha_2.fits", in: dir, pixel: 1250, cards: Self.asi("'Light Frame'", filter: "'Ha'", exptime: "300.0"))
    try TestFITS.write("l_1.fits", in: dir, pixel: 900, cards: Self.asi("'Light Frame'", filter: "'L'", exptime: "120.0"))
    try TestFITS.write("dark_1.fits", in: dir, pixel: 600, cards: Self.asi("'Dark Frame'", exptime: "300.0"))
    try TestFITS.write("flat_l.fits", in: dir, pixel: 30000, cards: Self.asi("'Flat Field'", filter: "'L'", exptime: "2.0"))
    try TestFITS.write("bias_1.fits", in: dir, pixel: 600, cards: Self.asi("'Bias Frame'", exptime: "0.0"))
    try Data("fake".utf8).write(to: dir.appendingPathComponent("moon.ser"))

    let inventory = try Self.scan(dir)
    #expect(inventory.countsByType == [.light: 3, .dark: 1, .flat: 1, .bias: 1])
    let ha = try #require(inventory.sets.first { $0.key.type == .light && $0.key.filter == "Ha" })
    #expect(ha.count == 2)
    #expect(ha.totalIntegrationMs == 600_000)
    #expect(Set(inventory.frames.filter { $0.type == .light }.map(\.filter)) == ["Ha", "L"])
  }

  @Test("old ASICAP colour: EXPOINUS makes it a 90 s light, the CFA stays", .scratchDirectory)
  func testInventoryBuilder_expoinusOSC() throws {
    let dir = try ScratchDirectory.url
    try TestFITS.write("osc_0001.fits", in: dir, pixel: 2400, cards: ["GAIN": "200", "BAYERPAT": "'GRBG'", "EXPOINUS": "90000000"])
    let inventory = try Self.scan(dir)
    let frame = try #require(inventory.frames.first)
    #expect(frame.exposureMs == 90000)
    #expect(frame.type == .light)
    #expect(frame.bayer == "GRBG")
    #expect(inventory.colorModel == .osc)
  }

  @Test("a mono rig's BAYERPAT is cleared on filtered lights and their calibration", .scratchDirectory)
  func testInventoryBuilder_spuriousBayer() throws {
    let dir = try ScratchDirectory.url
    for (index, filter) in ["'L'", "'R'", "'G'", "'B'", "'Ha'"].enumerated() {
      try TestFITS.write(
        "light_\(index).fits", in: dir, pixel: 2400,
        cards: ["IMAGETYP": "'Light'", "FILTER": filter, "BAYERPAT": "'GRBG'", "EXPOINUS": "120000000"])
    }
    try TestFITS.write("dark_0.fits", in: dir, pixel: 800, cards: ["IMAGETYP": "'Dark'", "BAYERPAT": "'GRBG'", "EXPOINUS": "120000000"])
    try TestFITS.write("bias_0.fits", in: dir, pixel: 500, cards: ["IMAGETYP": "'Bias'", "BAYERPAT": "'GRBG'", "EXPOINUS": "1000"])
    let inventory = try Self.scan(dir)
    #expect(inventory.frames.count == 7)
    #expect(inventory.frames.allSatisfy { $0.bayer.isEmpty })
    #expect(inventory.colorModel == .mono)
    #expect(inventory.sets.contains { $0.key.type == .light })
  }

  @Test(
    "the colour verdict: wheel filters, a CFA card, three planes, both",
    .scratchDirectory,
    arguments: [("mono", ColorModel.mono, 2), ("bayer", .osc, 1), ("rgb", .osc, 1), ("mixed", .mixed, 2)])
  func testInventoryBuilder_colorModel(seed: String, expected: ColorModel, lights: Int) throws {
    let dir = try ScratchDirectory.url
    let light = ["IMAGETYP": "'Light'"]
    let rgb = [[UInt16](repeating: 1200, count: 64), [UInt16](repeating: 1100, count: 64), [UInt16](repeating: 900, count: 64)]
    switch seed {
    case "mono":
      try TestFITS.write("l.fits", in: dir, pixel: 1200, cards: light.merging(["FILTER": "'L'"]) { $1 })
      try TestFITS.write("r.fits", in: dir, pixel: 1200, cards: light.merging(["FILTER": "'R'"]) { $1 })
    case "bayer":
      try TestFITS.write("a.fits", in: dir, pixel: 1200, cards: light.merging(["BAYERPAT": "'RGGB'"]) { $1 })
    case "rgb":
      try TestFITS.write("rgb.fits", in: dir, width: 8, height: 8, planes: rgb, cards: light)
    default:
      try TestFITS.write("l.fits", in: dir, pixel: 1200, cards: light.merging(["FILTER": "'L'"]) { $1 })
      try TestFITS.write("rgb.fits", in: dir, width: 8, height: 8, planes: rgb, cards: light)
    }
    let inventory = try Self.scan(dir)
    #expect(inventory.colorModel == expected)
    #expect(inventory.frames.count { $0.type == .light } == lights)
  }

  static func mosaic(_ size: Int, flat: Bool) -> [UInt16] {
    (0..<size * size).map { index in
      let (x, y) = (index % size, index / size)
      if flat { return 5000 }
      return y % 2 == 0 && x % 2 == 0 ? 5300 : y % 2 == 1 && x % 2 == 1 ? 5020 : 5040
    }
  }

  @Test("a dual-band clip on a colour camera stays one-shot-colour on disk", .scratchDirectory)
  func testInventoryBuilder_dualbandFolder() throws {
    let dir = try ScratchDirectory.url
    for name in ["l_1.fits", "l_2.fits", "l_3.fits"] {
      try TestFITS.write(
        name, in: dir, width: 16, height: 16, planes: [Self.mosaic(16, flat: false)],
        cards: [
          "IMAGETYP": "'Light Frame'", "EXPTIME": "120.0", "GAIN": "100", "BAYERPAT": "'RGGB'",
          "FILTER": "'L-eXtreme'", "INSTRUME": "'ZWO ASI2600MC Pro'",
        ])
    }
    let inventory = try Self.scan(dir)
    #expect(inventory.frames.allSatisfy { $0.bayer == "RGGB" })
    #expect(inventory.colorModel == .osc)
  }

  @Test("lights and calibration in two folders merge into one complete inventory", .scratchDirectory)
  func testInventoryBuilder_scanMany() throws {
    let root = try ScratchDirectory.url
    let lights = root.appendingPathComponent("lights")
    let calibration = root.appendingPathComponent("calib")
    try TestFITS.write("l_1.fits", in: lights, pixel: 900, cards: Self.asi("'Light Frame'", filter: "'L'", exptime: "120.0"))
    try TestFITS.write("l_2.fits", in: lights, pixel: 920, cards: Self.asi("'Light Frame'", filter: "'L'", exptime: "120.0"))
    try TestFITS.write("dark_1.fits", in: calibration, pixel: 600, cards: Self.asi("'Dark Frame'", exptime: "120.0"))
    try TestFITS.write("flat_l.fits", in: calibration, pixel: 30000, cards: Self.asi("'Flat Field'", filter: "'L'", exptime: "2.0"))
    try TestFITS.write("bias_1.fits", in: calibration, pixel: 600, cards: Self.asi("'Bias Frame'", exptime: "0.0"))

    let solo = try Self.scan(lights)
    #expect(solo.warnings.joined().contains("no darks in this folder"))
    let merged = try Self.builder.scan(paths: [lights.path, calibration.path])
    #expect(merged.countsByType == [.light: 2, .dark: 1, .flat: 1, .bias: 1])
    #expect(!merged.warnings.joined().contains("no darks in this folder"))
    #expect(!merged.warnings.joined().contains("no flats in this folder"))
    #expect(merged.root == root.path)
  }

  @Test("no folder is an error")
  func testInventoryBuilder_noFolders() {
    #expect(throws: InspectError.noFolders) { try Self.builder.scan(paths: []) }
  }

  @Test(
    "the common parent of several roots",
    arguments: [
      (["/a/b/c", "/a/b/d"], "/a/b"), (["/a/b", "/a/b/c"], "/a/b"), (["/a/b/c"], "/a/b/c"),
      (["/a/x", "/b/y"], "/"),
    ])
  func testInventoryBuilder_commonParent(roots: [String], expected: String) {
    #expect(InventoryBuilder.commonParent(roots) == expected)
  }

  @Test("an excluded set is dropped before the filter mapping and reported", .scratchDirectory)
  func testInventoryBuilder_excludeBeforeMapping() throws {
    let dir = try ScratchDirectory.url
    for index in 0..<2 {
      try TestFITS.write("v_\(index).fits", in: dir, cards: Self.asi("'Light Frame'", filter: "'V'", exptime: "120.0"))
    }
    for index in 0..<3 {
      try TestFITS.write("l_\(index).fits", in: dir, cards: Self.asi("'Light Frame'", filter: "'L'", exptime: "120.0"))
    }
    let canonical = try Self.scan(dir)
    // V normalizes to G at read time; the exclusion token is the canonical scan's.
    let green = try #require(canonical.sets.first { $0.key.filter == "G" }).key.id
    var overrides = InspectOverrides()
    overrides.excludeSets = [green]
    overrides.filterMap = ["G": "R"]
    let inventory = try Self.builder.scan(paths: [dir.path], overrides: overrides)
    #expect(inventory.frames.count == 3)
    #expect(!inventory.sets.contains { ["G", "R"].contains($0.key.filter) })
    #expect(inventory.warnings.contains("2 frame(s) in 1 set(s) excluded by user (stray-light artifact)"))
  }
}
