import Foundation
import StackKit
import TestSupport
import Testing

/// Translated from `wheelslot_test.go`, `sharpcap_nested_test.go` and `channel_test.go`:
/// mono captures without a FILTER card, named by wheel slot or by the wheel's order.
@Suite("InventoryBuilder.scan — filters from wheel slots and wheel order")
struct InventoryBuilderWheelTests {
  static let builder = InventoryBuilderTests.builder

  static func slotFrame(_ name: String, in dir: URL, slot: Int) throws {
    try TestFITS.write(
      name, in: dir, width: 16, height: 16, pixel: UInt16(1000 + slot * 100),
      cards: ["GAIN": "300", "EXPOINUS": "30000000", "CCD-TEMP": "-15.0"])
    let body =
      "EFW Slot = \(slot)(Alias: \(slot))\nExposure = 30s\nGain = 300\nTemperature = -15.0 C\n"
    try Data(body.utf8).write(to: dir.appendingPathComponent(name + ".txt"))
  }

  static func lightFilters(_ inventory: Inventory) -> [String: Int] {
    inventory.frames.filter { $0.type == .light }.reduce(into: [:]) {
      $0[$1.filter, default: 0] += 1
    }
  }

  @Test(
    "physical slots win over an off-by-one info.txt; a sibling folder uses the default wheel",
    .scratchDirectory)
  func testInventoryBuilder_wheelSlotDespiteOffByOne() throws {
    let root = try InventoryBuilderFallbackTests.folder("scan")
    let capObj = root.appendingPathComponent("M33/CapObj")
    try FileManager.default.createDirectory(at: capObj, withIntermediateDirectories: true)
    try Data("L R G B Ha\nL L\n300 gain\n-15°\n".utf8).write(
      to: capObj.appendingPathComponent("info.txt"))
    for (index, slot) in [1, 2, 3, 4, 5, 1].enumerated() {
      try Self.slotFrame(
        "2021-08-14-0\(index)00_6-\(slot)-CapObj_0000.FIT",
        in: capObj.appendingPathComponent("2021-08-14_0\(index)_00_00Z"), slot: slot)
    }
    let sibling = root.appendingPathComponent("M33/CapObj_0")
    try Self.slotFrame(
      "2021-08-13-2347_8-1-CapObj_0000.FIT",
      in: sibling.appendingPathComponent("2021-08-13_23_47_49Z"), slot: 1)

    let inventory = try Self.builder.scan(paths: [capObj.path, sibling.path])
    #expect(Self.lightFilters(inventory) == ["L": 3, "R": 1, "G": 1, "B": 1, "Ha": 1])
    #expect(inventory.frames.filter { $0.type == .light }.allSatisfy { $0.classSource == .wheel })
  }

  @Test(
    "capture order is not slot order: the legend is learned per folder (ngc6992)", .scratchDirectory
  )
  func testInventoryBuilder_narrowbandByPhysicalSlot() throws {
    let root = try InventoryBuilderFallbackTests.folder("scan").appendingPathComponent("ngc6992")
    let autorun = root.appendingPathComponent("autorun")
    try FileManager.default.createDirectory(at: autorun, withIntermediateDirectories: true)
    try Data("O3 250 gain\nHa 250 gain\nL 100 gain\nR 100\nG 100\n10 x 60s\n".utf8)
      .write(to: autorun.appendingPathComponent("info.txt"))
    let steps = [
      ("2020-07-12_21_00_00Z", 4), ("2020-07-12_21_10_00Z", 5), ("2020-07-12_21_20_00Z", 1),
      ("2020-07-12_21_30_00Z", 2), ("2020-07-12_21_40_00Z", 3),
    ]
    for (index, step) in steps.enumerated() {
      try Self.slotFrame(
        "2020-07-12-21\(index)0_6-\(step.1)-autorun_0000.FIT",
        in: autorun.appendingPathComponent(step.0),
        slot: step.1)
    }
    let inventory = try Self.builder.scan(paths: [root.path])
    #expect(Self.lightFilters(inventory) == ["L": 1, "R": 1, "G": 1, "Ha": 1, "OIII": 1])
    #expect(inventory.frames.filter { $0.type == .light }.allSatisfy { $0.classSource == .wheel })
  }

  @Test("no sidecar, a bare data/ folder: the file-name slot names the filter", .scratchDirectory)
  func testInventoryBuilder_filenameSlot() throws {
    let data = try InventoryBuilderFallbackTests.folder("scan").appendingPathComponent("m27/data")
    for (index, slot) in [1, 2, 3, 4].enumerated() {
      try TestFITS.write(
        "2019-08-29_2\(index)_00_00Z/2019-08-29-22\(index)0_5-\(slot)-L_0000.FIT", in: data,
        width: 16,
        height: 16, pixel: UInt16(1000 + slot * 50), cards: ["GAIN": "250", "EXPOINUS": "60000000"])
    }
    let inventory = try Self.builder.scan(paths: [data.path])
    #expect(Self.lightFilters(inventory) == ["L": 1, "R": 1, "G": 1, "B": 1])
    #expect(inventory.frames.allSatisfy { $0.classSource == .wheel })
  }

  static func capObjFrame(
    _ root: URL, _ kind: String, _ session: String, _ name: String,
    _ settings: (slot: Int, microseconds: Int, gain: Int)
  ) throws {
    let (slot, microseconds, gain) = settings
    let dir = root.appendingPathComponent("\(kind)/CapObj/\(session)")
    try TestFITS.write(
      name, in: dir, width: 16, height: 16, pixel: UInt16(1000 + slot * 100),
      cards: ["GAIN": "\(gain)", "EXPOINUS": "\(microseconds)", "CCD-TEMP": "-25.0"])
    let body =
      "EFW Slot = \(slot)(Alias: \(slot))\nGain = \(gain)\nBrightness = 10\nTemperature = -25.0 C\n"
    try Data(body.utf8).write(to: dir.appendingPathComponent(name + ".txt"))
  }

  @Test(
    "SharpCap's CapObj under darks/flats/offset types by the grandparent; flats split per slot",
    .scratchDirectory)
  func testInventoryBuilder_capObjUnderCalibration() throws {
    let root = try InventoryBuilderFallbackTests.folder("scan")
    for slot in 1...3 {
      for index in 0..<2 {
        try Self.capObjFrame(
          root, "triplet_m66", "2023-02-27_22_55_39Z",
          "2023-02-27-2255_6-\(slot)-CapObj_000\(index).FIT", (slot, 30_000_000, 250))
        try Self.capObjFrame(
          root, "flats", "2023-02-28_06_00_34Z", "2023-02-28-0600_5-\(slot)-CapObj_000\(index).FIT",
          (slot, 4794, 0))
      }
    }
    for index in 0..<2 {
      try Self.capObjFrame(
        root, "darks", "2023-02-28_05_09_49Z", "2023-02-28-0509_8-2-CapObj_000\(index).FIT",
        (2, 45_000_000, 400))
      try Self.capObjFrame(
        root, "offset", "2023-02-28_05_52_24Z", "2023-02-28-0552_4-1-CapObj_000\(index).FIT",
        (1, 32, 400))
    }
    let inventory = try Self.builder.scan(paths: [root.path])
    #expect(inventory.countsByType == [.light: 6, .dark: 2, .flat: 6, .bias: 2])
    let flats = inventory.sets.filter { $0.key.type == .flat }.reduce(into: [String: Int]()) {
      $0[$1.key.filter, default: 0] += $1.count
    }
    #expect(flats == ["L": 2, "R": 2, "G": 2])
    #expect(inventory.sets.filter { $0.key.type == .dark }.map(\.key.filter) == [""])
    #expect(inventory.sets.filter { $0.key.type == .bias }.map(\.key.filter) == [""])
  }

  static func dateObs(_ second: Int) -> String {
    String(
      format: "'2025-03-28T%02d:%02d:%02d.000'", second / 3600, (second % 3600) / 60, second % 60)
  }

  @Test("unlabeled lights separate into five sets by the wheel's order", .scratchDirectory)
  func testInventoryBuilder_detectsUnlabeledChannels() throws {
    let dir = try InventoryBuilderFallbackTests.folder("scan")
    let levels: [String: UInt16] = ["L": 3000, "R": 1100, "G": 1180, "B": 1050, "Ha": 300]
    let order = ["L", "R", "G", "B", "Ha"]
    var second = 0
    for (block, filter) in order.enumerated() {
      if block > 0 { second += 200 }
      for index in 0..<6 {
        try TestFITS.write(
          String(format: "img_%02d_%02d.fits", block, index), in: dir, width: 16, height: 16,
          pixel: levels[filter] ?? 0,
          cards: [
            "GAIN": "300", "OFFSET": "50", "CCD-TEMP": "-20.0", "XBINNING": "1", "EXPTIME": "30.0",
            "DATE-OBS": Self.dateObs(second),
          ])
        second += 31
      }
    }
    let inventory = try Self.builder.scan(paths: [dir.path])
    #expect(inventory.sets.count { $0.key.type == .light } == 5)
    let detection = try #require(inventory.channelDetection)
    #expect(detection.runs.map(\.filter) == order)
    #expect(detection.overallConfidence > 0.3)
    #expect(inventory.frames.allSatisfy { $0.classSource == .signal && !$0.filter.isEmpty })
  }

  @Test("labeled filters stay metadata-driven: no detection", .scratchDirectory)
  func testInventoryBuilder_labeledFilters() throws {
    let dir = try InventoryBuilderFallbackTests.folder("scan")
    for (block, filter) in ["L", "R", "G", "B"].enumerated() {
      for index in 0..<4 {
        try TestFITS.write(
          "Light_\(filter)_0\(index).fits", in: dir, width: 16, height: 16, pixel: 1500,
          cards: [
            "IMAGETYP": "'Light Frame'", "FILTER": "'\(filter)'", "GAIN": "300", "OFFSET": "50",
            "CCD-TEMP": "-20.0",
            "XBINNING": "1", "EXPTIME": "30.0", "DATE-OBS": Self.dateObs(block * 300 + index * 31),
          ])
      }
    }
    let inventory = try Self.builder.scan(paths: [dir.path])
    #expect(inventory.sets.count { $0.key.type == .light } == 4)
    #expect(inventory.channelDetection == nil)
    #expect(!inventory.frames.contains { $0.classSource == .signal })
  }
}
