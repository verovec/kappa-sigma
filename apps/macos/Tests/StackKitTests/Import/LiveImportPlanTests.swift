import Foundation
import StackKit
import TestSupport
import Testing

/// The Import plan of the real M31-DB capture (case (c) of 0044), picked as ONE folder the way the
/// sheet picks it, against the recorded inventory and calibration of that case.
@Suite(
  "Live import plan — the M31-DB capture as the sheet scans it", .liveFixtures, .tags(.live),
  .serialized, .timeLimit(.minutes(5)))
struct LiveImportPlanTests {
  static func planner() throws -> (ImportPlanner, URL) {
    let oracle = try LiveInventoryOracleTests.liveCase("m31-db")
    let folder = LiveInventoryOracleTests.captures.appendingPathComponent("M31-DB")
    guard FileManager.default.fileExists(atPath: folder.path) else {
      try Test.cancel("M31-DB absent under ~/Documents/astro/captures")
    }
    let zone = try TimeZone(identifier: oracle.manifest.timezone).unwrapped("timezone")
    return (ImportPlanner(builder: InventoryBuilder(timeZone: zone)), folder)
  }

  @Test(
    "one night of 36 colour lights; the plan builds the −19 °C dark, the night's flat, the bias")
  func testLiveImportPlan_m31db() throws {
    let (planner, folder) = try Self.planner()
    let plan = try planner.plan(ImportRequest(paths: [folder.path]), library: [])

    let lights = plan.nights.flatMap(\.sets).filter { $0.type == .light }
    #expect(lights.map(\.count) == [36])
    #expect(lights.first?.key.color == true)
    #expect(plan.nights.map(\.session).filter { !$0.isEmpty }.count == 1)
    let channel = try #require(plan.calibration.first)
    #expect(
      channel.cells.map(\.status) == [.build(frames: 2), .build(frames: 20), .build(frames: 15)])
    #expect(
      channel.notes.first
        == "no RGB flat — using the session flat (corrects shared dust/vignetting)")
    #expect(!channel.hasGap)
  }

  @Test("a filter-set override is the verdict the plan shows, where the pixels left it unknown")
  func testLiveImportPlan_filterSetOverride() throws {
    let (planner, folder) = try Self.planner()
    var request = ImportRequest(paths: [folder.path])
    let plain = try planner.plan(request, library: [])
    let light = try #require(plain.nights.flatMap(\.sets).first { $0.type == .light })
    #expect(light.filterSet == .unknown, "recorded: no verdict for this night")

    request.filterSets = [light.id: .dualband]
    let overridden = try planner.plan(request, library: [])
    let row = try #require(overridden.nights.flatMap(\.sets).first { $0.id == light.id })
    #expect(row.filterSet == .dualband)
    #expect(overridden.inventory.nightFilterSet(light.key.session) == .dualband)
  }
}
