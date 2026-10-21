import Foundation
import StackKit
import Testing

/// `CoverageMatrix`: each light set's dark, flat and bias as the matcher decided them, under its
/// night, with the gap count the journey shows (0078). No second matching rule (R2).
@Suite("CoverageMatrix — calibration coverage of every light set, the matcher's verdict as is")
struct CoverageMatrixTests {
  static let light = CalibrationFixtures.light("L", exposureMs: 300_000, tempC: -15)

  static func plan(
    lights: [FrameSet], extra: [FrameSet] = [], library: [CalibrationMaster],
    exclude: [String] = []
  ) -> ImportPlan {
    var inventory = Inventory(root: "", frames: [])
    inventory.sets = lights + extra
    var request = ImportRequest(paths: ["/c"])
    request.calibExclude = exclude
    return ImportPlan(inventory: inventory, library: library, request: request)
  }

  static let library = [
    CalibrationFixtures.master(.bias, path: "/lib/bias.fits", frames: 8, fromLibrary: true),
    CalibrationFixtures.master(
      .dark, path: "/lib/dark300.fits", exposureMs: 300_000, tempC: -15, frames: 5,
      fromLibrary: true),
    CalibrationFixtures.master(
      .flat, path: "/lib/flatL.fits", filter: "L", frames: 20, fromLibrary: true),
  ]

  @Test("library masters, a flat built from this capture, an exclusion and a gap")
  func testStatuses() throws {
    let covered = CoverageMatrix(
      plan: Self.plan(lights: [CalibrationFixtures.set(Self.light)], library: Self.library))
    #expect(
      covered.rows.first?.cells.map(\.status) == [
        .library(path: "/lib/dark300.fits", frames: 5), .library(path: "/lib/flatL.fits", frames: 20),
        .library(path: "/lib/bias.fits", frames: 8),
      ])
    #expect(covered.gaps == 0)

    let flats = CalibrationFixtures.set(CalibrationFixtures.calibrationKey(.flat, filter: "L"), count: 12)
    let built = CoverageMatrix(
      plan: Self.plan(
        lights: [CalibrationFixtures.set(Self.light)], extra: [flats],
        library: Array(Self.library.prefix(2))))
    #expect(built.rows.first?.cells[1].status == .build(frames: 12))

    // A 120 s dark scaled to 300 s needs the bias: excluding the bias drops the dark too.
    let (inventory, library, light) = ImportPlanTests.optInventory()
    let gapped = CoverageMatrix(
      plan: Self.plan(
        lights: inventory.sets, library: library,
        exclude: [CalibrationMatcher.suggestionID(light, role: .bias)]))
    let row = try #require(gapped.rows.first)
    #expect(
      row.cells.map(\.status) == [
        .missing, .missing, .excluded(.library(path: "/lib/bias.fits", frames: 8)),
      ])
    // The matcher's reasons, verbatim.
    #expect(row.notes.contains { $0.hasPrefix("dark skipped") })
    #expect(gapped.gaps == 1)
  }

  @Test("rows sit under their night, nights in order then filters in canonical order")
  func testRowsByNight() throws {
    let sets = [
      ("R", "2026-10-18"), ("L", "2026-10-18"), ("L", "2026-10-17"),
    ].map { filter, night in
      var key = CalibrationFixtures.light(filter, exposureMs: 300_000, tempC: -15)
      key.session = night
      return CalibrationFixtures.set(key)
    }
    let matrix = CoverageMatrix(plan: Self.plan(lights: sets, library: Self.library))
    #expect(matrix.rows.map(\.night) == ["2026-10-17", "2026-10-18", "2026-10-18"])
    #expect(matrix.rows.map(\.channel.filter) == ["L", "L", "R"])
    // R has no flat of its own: the matcher falls back and says so; not a gap.
    #expect(matrix.gaps == 0)
    #expect(matrix.rows.last?.notes.contains { $0.contains("no R flat") } == true)
  }

  @Test("a single-night scan keeps no night in its keys: the frames' night is shown")
  func testNightFromFrames() throws {
    var set = CalibrationFixtures.set(Self.light, count: 2)
    set.frames = set.frames.map { frame in
      var frame = frame
      frame.session = "2026-09-22"
      return frame
    }
    let matrix = CoverageMatrix(plan: Self.plan(lights: [set], library: Self.library))
    #expect(matrix.rows.map(\.night) == ["2026-09-22"])
  }
}
