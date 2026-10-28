import Foundation
import StackKit
import TestSupport
import Testing

/// The fallbacks of a scan when headers and names say little: pixel curves, unreadable files,
/// unnamed wheel slots, and the completeness warnings (`classifyUnknowns`, `addWarnings`,
/// `warnUnnamedWheelSlots`).
@Suite("InventoryBuilder.scan — curves, unreadable frames, unnamed slots, warnings")
struct InventoryBuilderFallbackTests {
  static let builder = InventoryBuilderTests.builder

  /// A folder deep enough that the scratch path's own ancestors (macOS temp folders such as
  /// `/var/folders/xx/r_…`, whose first word reads as a filter) fall outside the six-level
  /// folder lookup.
  static func folder(_ name: String) throws -> URL {
    try ScratchDirectory.url.appendingPathComponent("pad1/pad2/pad3/\(name)")
  }

  @Test(
    "frames nothing typed are classified by their curves, with a warning each", .scratchDirectory)
  func testInventoryBuilder_curveClassification() throws {
    let dir = try Self.folder("session")
    try TestFITS.write("a_flat.fits", in: dir, pixel: 30000, cards: ["EXPTIME": "2.0"])
    try TestFITS.write("b_zero.fits", in: dir, pixel: 300, cards: ["EXPTIME": "0.0"])
    let inventory = try Self.builder.scan(paths: [dir.path])
    #expect(inventory.frames.map(\.type) == [.flat, .bias])
    #expect(inventory.frames.allSatisfy { $0.classSource == .heuristic })
    let curves = inventory.warnings.filter { $0.contains("by curve heuristic") }
    #expect(curves.count == 2)
    #expect(
      curves.first
        == "a_flat.fits has no IMAGETYP/type folder; classified as FLAT by curve heuristic "
        + "(median 30000, peaks 0)"
    )
    #expect(inventory.warnings.contains("no light frames or videos found"))
  }

  @Test(
    "unreadable pixels keep a dated frame as a light; a frame with nothing is a leftover",
    .scratchDirectory)
  func testInventoryBuilder_unreadablePixels() throws {
    let dir = try Self.folder("session")
    let kept = try TestFITS.write(
      "kept.fits", in: dir, width: 64, height: 64, cards: ["EXPTIME": "30.0"])
    let leftover = try TestFITS.write("leftover.fits", in: dir, width: 64, height: 64, cards: [:])
    for url in [kept, leftover] {
      try Data(Data(contentsOf: url).prefix(2880 + 16)).write(to: url)
    }
    try Data("not a FITS file".utf8).write(to: dir.appendingPathComponent("broken.fits"))

    let inventory = try Self.builder.scan(paths: [dir.path])
    #expect(inventory.frames.map(\.type) == [.light, .unknown])
    #expect(inventory.warnings.contains { $0.hasPrefix("skip broken.fits:") })
    #expect(
      inventory.warnings.contains(
        "kept.fits has no IMAGETYP/type folder and its pixels could not be sampled — kept as LIGHT")
    )
    #expect(
      inventory.warnings.contains { $0.hasPrefix("leftover.fits has no type, no capture metadata") }
    )
    #expect(inventory.warnings.contains { $0.hasPrefix("no darks in this folder") })
    #expect(inventory.warnings.contains { $0.hasPrefix("no flats in this folder") })
    #expect(
      inventory.warnings.contains(
        "no bias or dark frames found — no read-noise calibration available"))
  }

  @Test("a wheel slot past the legend is named S<n> and warned once", .scratchDirectory)
  func testInventoryBuilder_unnamedSlot() throws {
    let dir = try Self.folder("data")
    for index in 0..<2 {
      try TestFITS.write(
        "2019-08-29-22\(index)0_5-9-L_0000.FIT", in: dir,
        cards: ["GAIN": "250", "EXPOINUS": "60000000"])
    }
    let inventory = try Self.builder.scan(paths: [dir.path])
    #expect(inventory.frames.map(\.filter) == ["S9", "S9"])
    #expect(inventory.warnings.filter { $0.contains("slot 9 has no name legend") }.count == 1)
  }

  @Test(
    "one physical slot named twice by info.txt is warned; the later name wins", .scratchDirectory)
  func testInventoryBuilder_slotLegendClash() throws {
    let root = try Self.folder("capture")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("L R\n".utf8).write(to: root.appendingPathComponent("info.txt"))
    for (index, run) in ["2021-08-14_00_10_00Z", "2021-08-14_00_20_00Z"].enumerated() {
      try TestFITS.write(
        "\(run)/2021-08-14-00\(index)0_6-1-CapObj_0000.FIT", in: root,
        cards: ["GAIN": "300", "EXPOINUS": "30000000"])
    }
    let inventory = try Self.builder.scan(paths: [root.path])
    #expect(inventory.frames.map(\.filter) == ["R", "R"])
    #expect(inventory.warnings.contains { $0.contains("slot 1 maps to both \"L\" and \"R\"") })
  }

  @Test("an already-debayered colour night is classified from its three planes")
  func testFilterSetScan_threePlanes() {
    let size = 8
    let plane = { (value: Double) in [Float](repeating: Float(value), count: size * size) }
    let reader = FilterSetScanTests.reader([
      "dual.fits": PixelPlanes(
        width: size, height: size, planes: [plane(506), plane(503), plane(502)]),
      "bias.fits": PixelPlanes(
        width: size, height: size, planes: [plane(500), plane(500), plane(500)]),
    ])
    var light = FilterSetScanTests.osc("dual.fits", .light, exposureMs: 120_000)
    var bias = FilterSetScanTests.osc("bias.fits", .bias, exposureMs: 0)
    light.bayer = ""
    light.channels = 3
    bias.bayer = ""
    bias.channels = 3
    var inventory = FilterSetScanTests.inventory([light, bias])
    FilterSetClassifier.annotate(&inventory, overrides: [:], pixels: reader)
    #expect(inventory.filterSets[FilterSetScanTests.id(inventory, .light, 120_000)] == .dualband)
  }
}
