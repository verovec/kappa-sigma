import Foundation
import StackKit
import TestSupport
import Testing

/// `IntegrationSummary`: what a capture holds, per filter × night, for the Données stage (0078).
@Suite("IntegrationSummary — integration per filter and night, with totals")
struct IntegrationSummaryTests {
  /// `count` lights of `filter` on `night`, `exposureS` each, at `tempC` (none when `nil`).
  static func lights(
    _ filter: String, night: String, count: Int, exposureS: Int, tempC: Double? = nil,
    filterSet: FilterSet = .unknown, color: Bool = false
  ) -> FrameSet {
    let frames = (0..<count).map { index in
      var frame = CaptureFrame(path: "/c/\(night)/\(filter)_\(exposureS)_\(index).fits")
      frame.type = .light
      frame.filter = filter
      frame.exposureMs = exposureS * 1000
      frame.session = night
      if let tempC {
        frame.hasTemp = true
        // A 0.5 °C spread across the set: the range must show it.
        frame.tempMilliC = Int(tempC * 1000) + (index % 2) * 500
      }
      return frame
    }
    let key = SetKey(
      type: .light, filter: filter, exposureMs: exposureS * 1000, session: night, color: color)
    return FrameSet(key: key, frames: frames, indices: Array(frames.indices), filterSet: filterSet)
  }

  /// A calibration set, never counted as integration.
  static func darks(count: Int) -> FrameSet {
    let frames = (0..<count).map { index in
      var frame = CaptureFrame(path: "/c/darks/d_\(index).fits")
      frame.type = .dark
      frame.exposureMs = 300_000
      return frame
    }
    return FrameSet(
      key: SetKey(type: .dark, exposureMs: 300_000), frames: frames, indices: Array(frames.indices))
  }

  static func inventory(_ sets: [FrameSet]) -> Inventory {
    var inventory = Inventory(root: "/c", frames: sets.flatMap(\.frames))
    inventory.sets = sets
    return inventory
  }

  /// One expected row: filter, clip filter, night, frames, exposures (s), integration (s).
  struct Expected: Equatable, CustomStringConvertible {
    let filter: String
    let filterSet: FilterSet
    let night: String
    let frames: Int
    let exposuresS: [Int]
    let integrationS: Int
    var description: String { "\(filter)/\(filterSet.rawValue)@\(night)" }

    init(_ row: IntegrationSummary.Row) {
      self.init(
        row.filter, row.filterSet, row.night, row.frames, row.exposuresMs.map { $0 / 1000 },
        row.integrationMs / 1000)
    }

    /// A mono row (no clip filter).
    init(_ filter: String, _ night: String, _ frames: Int, _ exposuresS: [Int], _ integrationS: Int)
    {
      self.init(filter, .unknown, night, frames, exposuresS, integrationS)
    }

    init(
      _ filter: String, _ filterSet: FilterSet, _ night: String, _ frames: Int,
      _ exposuresS: [Int], _ integrationS: Int
    ) {
      (self.filter, self.filterSet, self.night) = (filter, filterSet, night)
      (self.frames, self.exposuresS, self.integrationS) = (frames, exposuresS, integrationS)
    }
  }

  struct Case: CustomTestStringConvertible, Sendable {
    let name: String
    let sets: @Sendable () -> [FrameSet]
    let rows: [Expected]
    let frames: Int
    let integrationS: Int
    let nights: Int
    var testDescription: String { name }
  }

  static let cases: [Case] = [
    Case(
      name: "one-night colour, darks ignored",
      sets: {
        [
          lights("RGB", night: "2026-09-22", count: 36, exposureS: 300, filterSet: .dualband),
          darks(count: 20),
        ]
      },
      rows: [Expected("RGB", .dualband, "2026-09-22", 36, [300], 10_800)],
      frames: 36, integrationS: 10_800, nights: 1),
    Case(
      name: "two nights, broadband and dual-band apart",
      sets: {
        [
          lights("RGB", night: "2026-10-18", count: 33, exposureS: 300, filterSet: .dualband),
          lights("RGB", night: "2026-10-17", count: 40, exposureS: 180, filterSet: .broadband),
          lights("RGB", night: "2026-10-18", count: 37, exposureS: 180, filterSet: .broadband),
        ]
      },
      rows: [
        Expected("RGB", .broadband, "2026-10-17", 40, [180], 7_200),
        Expected("RGB", .broadband, "2026-10-18", 37, [180], 6_660),
        Expected("RGB", .dualband, "2026-10-18", 33, [300], 9_900),
      ],
      frames: 110, integrationS: 23_760, nights: 2),
    Case(
      name: "mono LRGB in canonical order, two exposures of L merged, undated last",
      sets: {
        [
          lights("B", night: "2026-03-01", count: 10, exposureS: 120),
          lights("L", night: "2026-03-01", count: 20, exposureS: 60),
          lights("L", night: "", count: 4, exposureS: 60),
          lights("L", night: "2026-03-01", count: 5, exposureS: 300),
          lights("R", night: "2026-03-01", count: 10, exposureS: 120),
          lights("G", night: "2026-03-01", count: 10, exposureS: 120),
        ]
      },
      rows: [
        Expected("L", "2026-03-01", 25, [60, 300], 2_700),
        Expected("L", "", 4, [60], 240),
        Expected("R", "2026-03-01", 10, [120], 1_200),
        Expected("G", "2026-03-01", 10, [120], 1_200),
        Expected("B", "2026-03-01", 10, [120], 1_200),
      ],
      frames: 59, integrationS: 6_540, nights: 1),
  ]

  @Test("rows per filter × night in canonical order, with totals", arguments: cases)
  func testRowsAndTotals(_ example: Case) {
    let summary = IntegrationSummary.make(inventory: Self.inventory(example.sets()))
    #expect(summary.rows.map(Expected.init) == example.rows)
    #expect(summary.frames == example.frames)
    #expect(summary.integrationMs == example.integrationS * 1000)
    #expect(summary.nights == example.nights)
    // Totals per filter add their rows up, in the rows' order.
    for total in summary.totals {
      let rows = summary.rows.filter {
        $0.filter == total.filter && $0.filterSet == total.filterSet
      }
      #expect(total.frames == rows.map(\.frames).reduce(0, +))
      #expect(total.integrationMs == rows.map(\.integrationMs).reduce(0, +))
    }
  }

  @Test("two targets of one night stay apart, rows and totals")
  func testTargetsApart() {
    var m33 = Self.lights("L", night: "2026-10-01", count: 3, exposureS: 60)
    m33.key.object = "M33"
    var m31 = Self.lights("L", night: "2026-10-01", count: 5, exposureS: 60)
    m31.key.object = "M31"
    let summary = IntegrationSummary.make(inventory: Self.inventory([m33, m31]))
    #expect(summary.rows.map(\.object) == ["M31", "M33"])
    #expect(summary.rows.map(\.frames) == [5, 3])
    #expect(summary.totals.map(\.object) == ["M31", "M33"])
    #expect(summary.targets == 2)
  }

  @Test("an undecided colour set takes its night's clip filter, as the run's lanes do")
  func testUndecidedSetTakesNightClipFilter() {
    let measured = Self.lights(
      "RGB", night: "2026-09-22", count: 4, exposureS: 300, filterSet: .dualband, color: true)
    let undecided = Self.lights("RGB", night: "2026-09-22", count: 2, exposureS: 120, color: true)
    var inventory = Self.inventory([measured, undecided])
    inventory.filterSets = [measured.key.id: .dualband]
    let summary = IntegrationSummary.make(inventory: inventory)
    #expect(summary.rows.map(\.filterSet) == [.dualband])
    #expect(summary.rows.first?.frames == 6)
  }

  @Test("a set's night is its first dated frame's, not an undated first frame's")
  func testNightSkipsUndatedFrame() {
    var set = Self.lights("L", night: "2026-09-22", count: 3, exposureS: 60)
    set.key.session = ""
    set.frames[0].session = ""
    #expect(ImportPlan.night(of: set) == "2026-09-22")
  }

  @Test("the temperature range of a row comes from its frames; none when no frame has one")
  func testTemperatureRange() {
    let summary = IntegrationSummary.make(
      inventory: Self.inventory([
        Self.lights("Ha", night: "2026-10-01", count: 4, exposureS: 300, tempC: -10),
        Self.lights("OIII", night: "2026-10-01", count: 4, exposureS: 300),
      ]))
    #expect(summary.rows.map(\.temperatureC) == [-10.0 ... -9.5, nil])
  }

  @Test(
    "the committed two-night case: its lights by night, totals equal to the scan", .scratchDirectory
  )
  func testCommittedTwoNightFixture() throws {
    let (input, _, planner) = try ImportPlanTests.fixture("golden-two-night")
    let plan = try planner.plan(ImportRequest(paths: [input.path]), library: [])
    let summary = IntegrationSummary.make(inventory: plan.inventory)
    let lights = plan.inventory.sets.filter { $0.key.type == .light }
    #expect(summary.frames == lights.map(\.count).reduce(0, +))
    #expect(summary.integrationMs == lights.map(\.totalIntegrationMs).reduce(0, +))
    #expect(Set(summary.rows.map(\.night)) == ["2020-05-15", "2024-03-01"])
    #expect(summary.totals.map(\.filter) == ["L", "R", "G", "B"])
  }
}
