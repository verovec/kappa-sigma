import Foundation
import StackKit
import TestSupport
import Testing

/// `ImportPlanner` and `ImportPlan`: what the Import sheet shows — the scan grouped by night, the
/// calibration each light set would get and every gap — from the committed oracle cases.
@Suite("ImportPlan — classification and calibration plan of a capture, before any run")
struct ImportPlanTests {
  /// A committed case rebuilt under a fresh scratch folder, and its planner.
  static func fixture(_ name: String) throws -> (input: URL, root: URL, planner: ImportPlanner) {
    let root = try InventoryBuilderFallbackTests.folder("scan")
    let input = root.appendingPathComponent("in")
    try HeaderFixture.load(name).materialize(under: input)
    let oracle = try OracleFixtureTests.committedCase(name)
    let zone = try TimeZone(identifier: oracle.manifest.timezone).unwrapped("timezone")
    return (input, root, ImportPlanner(builder: InventoryBuilder(timeZone: zone)))
  }

  static func lightID(_ plan: ImportPlan, filter: String) throws -> String {
    try #require(plan.inventory.sets.first { $0.key.type == .light && $0.key.filter == filter })
      .key.id
  }

  @Test(
    "overrides change the verdicts; without any, the plan's scan is the recorded inventory",
    .scratchDirectory)
  func testOverridesChangeVerdicts() throws {
    let (input, root, planner) = try Self.fixture("golden-single-night")
    var request = ImportRequest(paths: [input.path])
    let plain = try planner.plan(request, library: [])
    let recorded = try InventoryOracleTests.recorded(
      OracleFixtureTests.committedCase("golden-single-night"))
    let differences = InventoryJSON.differences(
      recorded: recorded,
      actual: InventoryJSON.object(plain.inventory) {
        $0.replacingOccurrences(of: root.path, with: "<ROOT>")
      })
    #expect(differences.isEmpty, "\(differences.joined(separator: "\n"))")
    #expect(plain.calibration.map(\.filter) == ["B", "G", "L", "R"])

    request.excludeSets = [try Self.lightID(plain, filter: "B")]
    request.filterMap = ["G": "ignore"]
    let overridden = try planner.plan(request, library: [])

    #expect(overridden.calibration.map(\.filter) == ["L", "R"])
    #expect(
      overridden.warnings.contains("3 frame(s) in 1 set(s) excluded by user (stray-light artifact)")
    )
  }

  @Test(
    "each light set's cell says library, build from N frames, excluded or missing",
    .scratchDirectory)
  func testPlanShowsGaps() throws {
    let (input, _, planner) = try Self.fixture("golden-single-night")
    var request = ImportRequest(paths: [input.path])
    let plain = try planner.plan(request, library: [])
    let lum = try #require(plain.calibration.first { $0.filter == "L" })
    #expect(lum.cells.map(\.role) == [.dark, .flat, .bias])
    #expect(lum.cells.map(\.status) == [.build(frames: 3), .build(frames: 3), .build(frames: 3)])

    let darks = try #require(plain.inventory.sets.first { $0.key.type == .dark }).key.id
    request.excludeSets = [darks]
    request.calibExclude = [CalibrationMatcher.suggestionID(lum.key, role: .flat)]
    let gaps = try planner.plan(request, library: [])
    let lumGaps = try #require(gaps.calibration.first { $0.filter == "L" })
    #expect(
      lumGaps.cells.map(\.status) == [.missing, .excluded(.build(frames: 3)), .build(frames: 3)])
    #expect(
      lumGaps.notes.contains { $0.contains("dark") }, "the gap is explained: \(lumGaps.notes)")
    #expect(lumGaps.hasGap)
    #expect(!lum.hasGap)
  }

  @Test(
    "a library master is named; the capture's own frames are not rebuilt over it",
    .scratchDirectory)
  func testPlanNamesLibraryMasters() throws {
    let (input, _, planner) = try Self.fixture("golden-single-night")
    var bias = CalibrationMaster(type: .bias, path: "/lib/master_BIAS_g100o10_b1.fits")
    bias.gain = 100
    bias.offset = 10
    bias.bin = 1
    bias.frameCount = 50
    bias.fromLibrary = true
    let plan = try planner.plan(ImportRequest(paths: [input.path]), library: [bias])
    let cells = try #require(plan.calibration.first { $0.filter == "L" }).cells
    #expect(cells.last?.status == .library(path: bias.path, frames: 50))
  }

  @Test("sets are grouped by night, lights first, in the scan's display order", .scratchDirectory)
  func testInventoryGroupedByNight() throws {
    let (input, _, planner) = try Self.fixture("golden-two-night")
    let plan = try planner.plan(ImportRequest(paths: [input.path]), library: [])
    #expect(plan.nights.map(\.session) == ["2020-05-15", "2024-03-01", ""])
    let first = try #require(plan.nights.first)
    #expect(first.sets.map(\.filter) == ["L", "R", "B"])
    #expect(first.sets.map(\.type) == [.light, .light, .flat])
    #expect(first.sets.map(\.count) == [2, 2, 3])
    #expect(plan.nights.last?.sets.map(\.type) == [.dark, .dark, .bias])
    #expect(plan.nights.flatMap(\.sets).count == plan.inventory.sets.count)
  }

  /// A 300 s light whose only dark is a 120 s library master: the dark is scaled (`-opt`), which
  /// needs the bias.
  static func optInventory() -> (Inventory, [CalibrationMaster], SetKey) {
    let light = CalibrationFixtures.light("L", exposureMs: 300_000, tempC: -15)
    var inventory = Inventory(root: "", frames: [])
    inventory.sets = [CalibrationFixtures.set(light)]
    let library = [
      CalibrationFixtures.master(.bias, path: "/lib/bias.fits", frames: 8, fromLibrary: true),
      CalibrationFixtures.master(
        .dark, path: "/lib/dark120.fits", exposureMs: 120_000, tempC: -15, frames: 5,
        fromLibrary: true),
    ]
    return (inventory, library, light)
  }

  @Test("a -opt dark dropped with its excluded bias is missing, not an exclusion to undo")
  func testOptDarkDroppedWithBias() throws {
    let (inventory, library, light) = Self.optInventory()
    var request = ImportRequest(paths: ["/c"])
    request.calibExclude = [CalibrationMatcher.suggestionID(light, role: .bias)]
    let plan = ImportPlan(inventory: inventory, library: library, request: request)
    let cells = try #require(plan.calibration.first).cells
    #expect(
      cells.map(\.status) == [
        .missing, .missing, .excluded(.library(path: "/lib/bias.fits", frames: 8)),
      ])
    #expect(plan.calibration.first?.notes.contains { $0.hasPrefix("dark skipped") } == true)
  }

  @Test("a calibration-only change replans the same scan and library, without rescanning")
  func testReplanKeepsScan() async throws {
    let (inventory, library, light) = Self.optInventory()
    let plan = ImportPlan(
      inventory: inventory, library: library, request: ImportRequest(paths: ["/c"]))
    #expect(plan.library == library)
    var request = ImportRequest(paths: ["/c"])
    request.calibExclude = [CalibrationMatcher.suggestionID(light, role: .dark)]
    let replanned = await ImportPlanner.replanned(plan, request: request)
    #expect(replanned.inventory == plan.inventory)
    #expect(
      replanned.calibration.first?.cells.first?.status
        == .excluded(.library(path: "/lib/dark120.fits", frames: 5)))
    #expect(ImportPlanner.needsScan(from: ImportRequest(paths: ["/c"]), to: request) == false)
    var mapped = request
    mapped.filterMap = ["L": "R"]
    #expect(ImportPlanner.needsScan(from: request, to: mapped))
  }
}
