import FilterKit
import StackKit
import Testing

/// Translated from `filterset_test.go` and `filterset_masters_test.go`: a dual-band night is never
/// flat-fielded with a broadband flat (memory `flat-matching-pitfalls`).
@Suite("Calibration filter sets — the clip filter gates flats, never darks")
struct CalibrationFilterSetTests {
  typealias Fixtures = CalibrationFixtures
  static let nightA = "2026-07-29"
  static let nightB = "2026-08-02"

  static func light(_ night: String) -> SetKey {
    SetKey(
      type: .light, object: "NGC7000", filter: Filter.color, exposureMs: 120_000, gain: 100,
      offset: 50, bin: 1, session: night, color: true)
  }

  static func flat(_ night: String, _ set: FilterSet, frames: Int) -> CalibrationMaster {
    Fixtures.master(
      .flat, path: "flat_\(night)_\(set.rawValue).fits", exposureMs: 2000, gain: 100, offset: 50,
      frames: frames, session: night, filterSet: set)
  }

  struct Row: Sendable, CustomTestStringConvertible {
    let testDescription: String
    var lightSet: FilterSet
    var masters: [CalibrationMaster]
    var expected: String?
    var note = ""
    var forbidden = ""
    var force = false
  }

  static let rows: [Row] = [
    Row(
      testDescription: "both known and equal: the same-set flat", lightSet: .dualband,
      masters: [flat(nightB, .broadband, frames: 50), flat(nightB, .dualband, frames: 20)],
      expected: "flat_2026-08-02_dualband.fits"),
    Row(
      testDescription: "the same-night correct flat wins, no advice", lightSet: .dualband,
      masters: [flat(nightA, .broadband, frames: 50), flat(nightA, .dualband, frames: 20)],
      expected: "flat_2026-07-29_dualband.fits", forbidden: "excluded"),
    Row(
      testDescription: "a cross-set flat is not a candidate, even alone", lightSet: .dualband,
      masters: [flat(nightB, .broadband, frames: 50)], expected: nil, note: "dualband"),
    Row(
      testDescription: "a deeper same-night cross-set flat loses", lightSet: .broadband,
      masters: [flat(nightA, .dualband, frames: 200), flat(nightB, .broadband, frames: 5)],
      expected: "flat_2026-08-02_broadband.fits"),
    Row(
      testDescription: "light unknown: today's ranking", lightSet: .unknown,
      masters: [flat(nightB, .broadband, frames: 5), flat(nightA, .dualband, frames: 5)],
      expected: "flat_2026-07-29_dualband.fits"),
    Row(
      testDescription: "flat unknown: today's ranking", lightSet: .dualband,
      masters: [flat(nightA, .unknown, frames: 5), flat(nightB, .dualband, frames: 50)],
      expected: "flat_2026-07-29_unknown.fits"),
    Row(
      testDescription: "two foreign clips are both named, in filter-set order",
      lightSet: .dualbandSII,
      masters: [flat(nightB, .dualband, frames: 20), flat(nightA, .broadband, frames: 50)],
      expected: nil, note: "are broadband/dualband"),
    Row(
      testDescription: "force applies a cross-set flat", lightSet: .dualband,
      masters: [flat(nightB, .broadband, frames: 50)], expected: "flat_2026-08-02_broadband.fits",
      force: true),
  ]

  @Test("the flat's filter set must equal the light's when both are known", arguments: rows)
  func testCalibrationFilterSet_gate(row: Row) {
    let selection = CalibrationMatcher.match(
      LightRef(key: Self.light(Self.nightA), filterSet: row.lightSet), masters: row.masters,
      force: row.force)
    #expect(selection.flat?.path == row.expected)
    let notes = selection.notes.joined(separator: " | ").lowercased()
    if !row.note.isEmpty { #expect(notes.contains(row.note)) }
    if !row.forbidden.isEmpty { #expect(!notes.contains(row.forbidden)) }
  }

  @Test("an unknown light set matches exactly like a plain key")
  func testCalibrationFilterSet_unknownIsIdentical() {
    let masters = [
      Self.flat("2026-08-02", .broadband, frames: 50),
      Self.flat("2026-07-29", .dualband, frames: 5),
    ]
    let light = Self.light("2026-07-29")
    #expect(
      CalibrationMatcher.match(LightRef(key: light), masters: masters)
        == CalibrationMatcher.match(LightRef(key: light, filterSet: .unknown), masters: masters))
  }

  @Test("darks and bias are closed-shutter: their filter set never gates them")
  func testCalibrationFilterSet_darksUnaffected() {
    let dark = Fixtures.master(
      .dark, path: "dark.fits", exposureMs: 120_000, gain: 100, offset: 50, frames: 30,
      filterSet: .broadband)
    let bias = Fixtures.master(
      .bias, path: "bias.fits", gain: 100, offset: 50, frames: 50, filterSet: .broadband)
    let selection = CalibrationMatcher.match(
      LightRef(key: Self.light(Self.nightA), filterSet: .dualband), masters: [dark, bias])
    #expect(selection.dark?.path == "dark.fits")
    #expect(selection.bias?.path == "bias.fits")
  }

  /// An OSC inventory: a light set per night with its verdict, plus calibration sets.
  static func scan(_ lights: [(String, FilterSet)], calibration: [SetKey]) -> Inventory {
    var inventory = Inventory(root: "", frames: [])
    inventory.colorModel = .osc
    inventory.sets =
      lights.map { Fixtures.set(light($0.0), count: 30) }
      + calibration.map { Fixtures.set($0, count: 20) }
    for (index, light) in lights.enumerated() where light.1.isKnown {
      inventory.filterSets[inventory.sets[index].key.id] = light.1
    }
    return inventory
  }

  static func oscCalibration(_ night: String, _ type: FrameType, exposureMs: Int = 0) -> SetKey {
    SetKey(
      type: type, filter: type == .flat ? Filter.color : "", exposureMs: exposureMs, gain: 100,
      offset: 50, bin: 1, session: night, color: true)
  }

  @Test(
    "a flat inherits its night's verdict; darks, bias and unmeasured nights stay unknown",
    arguments: [
      (
        [(nightA, FilterSet.dualband)], oscCalibration(nightA, .flat, exposureMs: 2000),
        FilterSet.dualband
      ),
      ([(nightA, .dualband)], oscCalibration(nightA, .dark, exposureMs: 120_000), .unknown),
      ([(nightA, .broadband)], oscCalibration(nightA, .bias), .unknown),
      ([(nightA, .unknown)], oscCalibration(nightA, .flat, exposureMs: 2000), .unknown),
      ([(nightA, .dualband)], oscCalibration(nightB, .flat, exposureMs: 2000), .unknown),
    ])
  func testCalibrationFilterSet_stamp(
    lights: [(String, FilterSet)], key: SetKey, expected: FilterSet
  ) {
    let inventory = Self.scan(lights, calibration: [key])
    var master = CalibrationMaster(type: MasterType(key.type) ?? .bias, path: "")
    master.stampFilterSet(of: key, in: inventory)
    #expect(master.filterSet == expected)
  }

  @Test("the light's ref takes its set's verdict, else its night's")
  func testCalibrationFilterSet_ref() {
    let inventory = Self.scan([(Self.nightA, .dualband)], calibration: [])
    var set = inventory.sets[0]
    #expect(LightRef(set, in: inventory).filterSet == .dualband)
    set.filterSet = .broadband
    #expect(LightRef(set, in: inventory).filterSet == .broadband)
  }
}
