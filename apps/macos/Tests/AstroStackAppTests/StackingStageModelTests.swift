import AstroStackApp
import Foundation
import StackKit
import Testing

/// `StackingStageModel` (card 0095): the light sets of the last scan grouped object → night, a
/// checkbox each, every set checked by default, one run per object with a checked set.
@MainActor
@Suite("StackingStageModel — series per object × night, defaults, scopes")
struct StackingStageModelTests {
  /// A capture frame of `object` (lights), or a calibration frame (`object` unused).
  nonisolated static func frame(
    _ type: FrameType, object: String = "", filter: String = "L", night: String = "",
    index: Int = 0, exposureMs: Int = 120_000
  ) -> CaptureFrame {
    var frame = CaptureFrame(
      path: "/c/\(object.isEmpty ? "cal" : object)/\(type)_\(filter)_\(night)_\(index).fits")
    frame.type = type
    frame.object = type == .light ? object : ""
    frame.filter = type == .light || type == .flat ? filter : ""
    frame.exposureMs = type == .bias ? 0 : exposureMs
    frame.gain = 100
    frame.offset = 50
    frame.binX = 1
    frame.binY = 1
    frame.session = night
    return frame
  }

  /// `objects` each shot `nights` with `perNight` L lights, plus two darks and two bias.
  nonisolated static func inventory(
    objects: [String], nights: [String] = [""], perNight: Int = 3
  ) -> Inventory {
    var frames: [CaptureFrame] = []
    for object in objects {
      for night in nights {
        for index in 0..<perNight {
          frames.append(frame(.light, object: object, night: night, index: index))
        }
      }
    }
    frames += [frame(.dark, index: 0), frame(.dark, index: 1), frame(.bias, index: 0)]
    var inventory = Inventory(root: "/c", frames: frames)
    inventory.colorModel = .mono
    inventory.regroup()
    return inventory
  }

  struct Case: Sendable, CustomTestStringConvertible {
    let objects: [String]
    let nights: [String]
    let groups: Int
    let seriesPerGroup: [Int]
    let runs: Int
    var testDescription: String { "\(objects) × \(nights)" }
  }

  @Test(
    "every set is checked by default: one object → one run, two → two, in object order",
    arguments: [
      Case(objects: ["M 31"], nights: [""], groups: 1, seriesPerGroup: [1], runs: 1),
      Case(
        objects: ["M 31", "IC 1848"], nights: [""], groups: 2, seriesPerGroup: [1, 1], runs: 2),
      Case(
        objects: ["M 31"], nights: ["2026-09-21", "2026-09-22"], groups: 1, seriesPerGroup: [2],
        runs: 1),
      Case(objects: [], nights: [""], groups: 0, seriesPerGroup: [], runs: 0),
    ])
  func testSeriesDefaultsAndQueue(_ row: Case) {
    let inventory = Self.inventory(objects: row.objects, nights: row.nights)
    let model = StackingStageModel(inventory: inventory)
    #expect(model.groups.count == row.groups)
    #expect(model.groups.map(\.object) == row.objects.sorted())
    #expect(model.groups.map { $0.nights.flatMap(\.series).count } == row.seriesPerGroup)
    #expect(model.groups.flatMap(\.nights).flatMap(\.series).allSatisfy { model.isChecked($0.id) })
    let scopes = model.scopes
    #expect(scopes.count == row.runs)
    #expect(scopes.map(\.object) == row.objects.sorted())
    #expect(scopes == RunScope.scopes(of: inventory), "every set: the scopes of the scan itself")
    #expect(model.isEmpty == row.objects.isEmpty)
    for series in model.groups.flatMap(\.nights).flatMap(\.series) {
      #expect(series.frames == 3 && series.integrationMs == 360_000 && series.filter == "L")
      #expect(series.exposureMs == 120_000 && series.gain == 100)
    }
  }

  @Test("a deselected night leaves its run's request; nothing checked for an object drops its run")
  func testDeselectedNightLeavesTheRun() throws {
    let inventory = Self.inventory(
      objects: ["IC 1848", "M 31"], nights: ["2026-09-21", "2026-09-22"])
    let model = StackingStageModel(inventory: inventory)
    let m31 = try #require(model.groups.first { $0.object == "M 31" })
    let firstNight = try #require(m31.nights.first { $0.night == "2026-09-21" })
    #expect(m31.nights.map(\.night) == ["2026-09-21", "2026-09-22"])
    for series in firstNight.series { model.set(series.id, checked: false) }
    #expect(!model.isChecked(firstNight.series[0].id))

    let scopes = model.scopes
    #expect(scopes.map(\.object) == ["IC 1848", "M 31"])
    let m31Scope = try #require(scopes.last)
    #expect(m31Scope.setIDs.allSatisfy { $0.hasSuffix("s:2026-09-22") })
    #expect(m31Scope.lights == 3)
    #expect(scopes.first?.lights == 6, "the other object keeps both nights")

    for series in m31.nights.flatMap(\.series) { model.set(series.id, checked: false) }
    #expect(model.scopes.map(\.object) == ["IC 1848"], "no checked set: no run for M 31")
    model.toggle(firstNight.series[0].id)
    #expect(model.scopes.count == 2)
  }

  @Test("a new scan keeps the choices made on sets it still has and checks the new ones")
  func testReplaceKeepsChoices() throws {
    let model = StackingStageModel(
      inventory: Self.inventory(objects: ["M 31"], nights: ["2026-09-21", "2026-09-22"]))
    let gone = try #require(model.groups[0].nights.first?.series.first?.id)
    model.set(gone, checked: false)
    model.replace(
      inventory: Self.inventory(
        objects: ["M 31", "NGC 7000"], nights: ["2026-09-21", "2026-09-22"]))
    #expect(!model.isChecked(gone))
    #expect(model.groups.map(\.object) == ["M 31", "NGC 7000"])
    #expect(model.scopes.map(\.lights) == [3, 6])
    model.replace(inventory: nil)
    #expect(model.isEmpty && model.scopes.isEmpty)
    // A dropped scan in between (Import, then Rescan) forgets no choice.
    model.replace(
      inventory: Self.inventory(
        objects: ["M 31", "NGC 7000"], nights: ["2026-09-21", "2026-09-22"]))
    #expect(!model.isChecked(gone))
    #expect(model.scopes.map(\.lights) == [3, 6])
  }
}
