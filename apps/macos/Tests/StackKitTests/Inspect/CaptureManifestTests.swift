import Foundation
import StackKit
import TestSupport
import Testing

/// Translated from `internal/inspect/manifest_test.go` and the unit half of `wheelslot_test.go`.
@Suite("CaptureManifest — hand-written info.txt legends, a fallback only")
struct CaptureManifestTests {
  static func filters(_ manifest: CaptureManifest, _ filter: String) -> [CaptureManifest.Slot] {
    manifest.slots.filter { $0.filter == filter }
  }

  @Test("the documented form: a filter sequence, then a per-filter gain map")
  func testCaptureManifest_canonical() {
    let manifest = CaptureManifest(parsing: "LLL RR GG BB Ha Ha\ngain L200 RGB250 Ha300\n")
    #expect(
      manifest.slots.map(\.filter) == ["L", "L", "L", "R", "R", "G", "G", "B", "B", "Ha", "Ha"])
    #expect(manifest.slots.allSatisfy { $0.hasGain })
    #expect(manifest.slots.map(\.gain) == [200, 200, 200, 250, 250, 250, 250, 250, 250, 300, 300])
  }

  @Test("m81: inline gains per line, a global exposure, a temperature, ignored prose")
  func testCaptureManifest_m81() {
    let manifest = CaptureManifest(
      parsing: """
        L L L L L L 0 gain
        R 0 gain
        G 0 gain
        B 0 gain
        Ha 180 gain

        Ha 50 gain 300s
        Ha 10 gain 300s
        Ha Ha 0 gain 300s

        120s
        -25°
        full moon j-1

        """)
    #expect(manifest.slots.count == 14)
    #expect(Self.filters(manifest, "L").count == 6)
    #expect(Self.filters(manifest, "Ha").map(\.gain) == [180, 50, 10, 0, 0])
    #expect(Self.filters(manifest, "L").first?.exposureMs == 120_000)
    #expect(Self.filters(manifest, "Ha").first { $0.gain == 50 }?.exposureMs == 300_000)
    #expect(manifest.hasTemp)
    #expect(manifest.tempMilliC == -25000)
    #expect(!manifest.warnings.isEmpty)
  }

  @Test("m33: repeated sequences take the global gain and exposure")
  func testCaptureManifest_m33() {
    let manifest = CaptureManifest(
      parsing: "LLL R G B Ha\nLLL R G B Ha\nLLL\nLLL\nLL\n30 s\n300 gain\n-15°")
    #expect(manifest.slots.count == 22)
    #expect(manifest.slots.allSatisfy { $0.hasGain && $0.gain == 300 && $0.exposureMs == 30000 })
    #expect(manifest.tempMilliC == -15000)
  }

  @Test("flats: a glued run, per-filter arrow exposures, gain 0 is a value")
  func testCaptureManifest_flats() {
    let manifest = CaptureManifest(
      parsing: """
        LLLRGBHaHa
        0 gain
        -15°
        L -> 2s
        R -> 7s
        G -> 6s
        B -> 6s
        Ha -> 200s
        histogram : debut 38400 - fin 51200 - avg - 40k/45k
        """)
    #expect(manifest.slots.count == 8)
    #expect(manifest.slots.allSatisfy { $0.hasGain && $0.gain == 0 })
    #expect(Self.filters(manifest, "L").first?.exposureMs == 2000)
    #expect(Self.filters(manifest, "R").first?.exposureMs == 7000)
    #expect(Self.filters(manifest, "Ha").first?.exposureMs == 200_000)
  }

  @Test("a numeric filter wheel names nothing and is warned")
  func testCaptureManifest_numericWheel() {
    let manifest = CaptureManifest(
      parsing: "filtre 1 2 3 4 5 1\n10 photo par filtre\n30s\n-30deg\n150 gain")
    #expect(manifest.slots.isEmpty)
    #expect(!manifest.warnings.isEmpty)
    #expect(manifest.hasTemp)
  }

  @Test(
    "a glued filter word expands greedily; any other letter refuses the word",
    arguments: [
      ("LLLRGBHaHa", Optional(["L", "L", "L", "R", "G", "B", "Ha", "Ha"])), ("Ha", ["Ha"]),
      ("OIII", ["OIII"]), ("RVB", ["R", "G", "B"]), ("gain", nil), ("moon", nil), ("L200", nil),
    ])
  func testCaptureManifest_expandFilterWord(word: String, expected: [String]?) {
    #expect(CaptureManifest.expandFilterWord(word) == expected)
  }

  @Test("a slot past the legend is a stable placeholder; the default wheel reaches SII")
  func testWheelSlots_filterForSlot() {
    let legend = ["L", "R", "G", "B", "Ha"]
    #expect(WheelSlots.filter(slot: 1, legend: legend) == "L")
    #expect(WheelSlots.filter(slot: 5, legend: legend) == "Ha")
    #expect(WheelSlots.filter(slot: 6, legend: legend) == "S6")
    #expect(WheelSlots.filter(slot: 6, legend: WheelSlots.defaultLegend) == "OIII")
    #expect(WheelSlots.filter(slot: 7, legend: WheelSlots.defaultLegend) == "SII")
  }

  static func unknownFrames(in dir: URL, runs: [String], perRun: [String]) throws -> [CaptureFrame]
  {
    try runs.flatMap { run in
      let folder = dir.appendingPathComponent(run)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      return perRun.map { CaptureFrame(path: folder.appendingPathComponent($0).path) }
    }
  }

  @Test("slots map onto capture folders in chronological order", .scratchDirectory)
  func testCaptureManifest_applyChronological() throws {
    let root = try ScratchDirectory.url
    let folder = root.appendingPathComponent("M101old")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("LL RR\n300 gain\n-15°\n".utf8).write(to: folder.appendingPathComponent("info.txt"))
    let runs = [
      "2021-08-14_00_40_00Z", "2021-08-14_00_10_00Z", "2021-08-14_00_30_00Z",
      "2021-08-14_00_20_00Z",
    ]
    var inventory = Inventory(
      root: root.path,
      frames: try Self.unknownFrames(in: folder, runs: runs, perRun: ["a.fit", "b.fit"]))
    CaptureManifest.apply(
      files: [folder.appendingPathComponent("info.txt").path], to: &inventory)

    let expected = [
      "2021-08-14_00_10_00Z": "L", "2021-08-14_00_20_00Z": "L", "2021-08-14_00_30_00Z": "R",
      "2021-08-14_00_40_00Z": "R",
    ]
    for frame in inventory.frames {
      let run = URL(fileURLWithPath: frame.path).deletingLastPathComponent().lastPathComponent
      #expect(frame.filter == expected[run])
      #expect(frame.type == .light)
      #expect(frame.gain == 300)
      #expect(frame.hasTemp)
      #expect(frame.classSource == .manifest)
    }
  }

  @Test("more slots than folders maps the aligned prefix and warns", .scratchDirectory)
  func testCaptureManifest_applyCountMismatch() throws {
    let root = try ScratchDirectory.url
    let folder = root.appendingPathComponent("set")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("L R Ha\n".utf8).write(to: folder.appendingPathComponent("info.txt"))
    var inventory = Inventory(
      root: root.path,
      frames: try Self.unknownFrames(
        in: folder, runs: ["2021-08-14_00_10_00Z", "2021-08-14_00_20_00Z"], perRun: ["a.fit"]))
    CaptureManifest.apply(
      files: [folder.appendingPathComponent("info.txt").path], to: &inventory)

    #expect(inventory.frames.map(\.filter) == ["L", "R"])
    #expect(inventory.frames.allSatisfy { $0.type == .light })
    #expect(!inventory.warnings.isEmpty)
  }
}
