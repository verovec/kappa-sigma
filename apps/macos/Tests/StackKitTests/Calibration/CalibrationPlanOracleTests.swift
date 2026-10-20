import Foundation
import StackKit
import TestSupport
import Testing

/// The plan against the legacy engine's `calibration.json` (0044 cases (a), (b): committed,
/// rebuilt from header fixtures; (c), (d): `LiveCalibrationPlanOracleTests`).
@Suite("Calibration plan oracle — masters and selections of the synthetic cases")
struct CalibrationPlanOracleTests {
  static func recorded(_ oracle: OracleCase) throws -> CalibrationPlanOracle.Object {
    let data = try Data(contentsOf: oracle.directory.appendingPathComponent("calibration.json"))
    return try (JSONSerialization.jsonObject(with: data) as? CalibrationPlanOracle.Object).unwrapped("calibration.json")
  }

  /// Builds the masters with a recording Siril and compares the plan with the recording.
  static func differences(_ oracle: OracleCase, inventory: Inventory, scratch: URL) async throws -> [String] {
    let run = scratch.appendingPathComponent("work/run_R")
    let built = try await MasterBuilder(runner: RecordingSiril().runner).build(
      inventory, into: run.appendingPathComponent("masters"), work: run)
    return CalibrationPlanOracle.differences(
      recorded: try recorded(oracle), masters: built.masters, inventory: inventory)
  }

  @Test(
    "chosen masters and gaps equal the recorded plan",
    .scratchDirectory, arguments: ["golden-single-night", "golden-two-night"])
  func testMatchesRecordedPlan(name: String) async throws {
    let root = try InventoryBuilderFallbackTests.folder("scan")
    let inventory = try MasterBuilderTests.scan(name, under: root)
    let differences = try await Self.differences(
      OracleFixtureTests.committedCase(name), inventory: inventory, scratch: root)
    #expect(differences.isEmpty, "\(differences.joined(separator: "\n"))")
  }
}

/// The real M31 captures against their recorded plans (OSC, per-night flats, filter sets).
@Suite(
  "Live calibration plan oracle — the M31 captures", .liveFixtures, .tags(.live), .serialized,
  .timeLimit(.minutes(5)))
struct LiveCalibrationPlanOracleTests {
  @Test(
    "chosen masters and gaps equal the recorded plan",
    .scratchDirectory, arguments: [("m31-db", ["M31-DB"]), ("m31-bb-db", ["M31-DB", "M31-BB"])])
  func testLiveCalibrationPlan(name: String, captures: [String]) async throws {
    let oracle = try LiveInventoryOracleTests.liveCase(name)
    let roots = captures.flatMap { capture in
      ["lights", "darks", "flats", "bias"].map {
        LiveInventoryOracleTests.captures.appendingPathComponent(capture).appendingPathComponent($0)
      }
    }
    guard roots.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
      try Test.cancel("captures \(captures) absent under ~/Documents/astro/captures")
    }
    let zone = try TimeZone(identifier: oracle.manifest.timezone).unwrapped("timezone")
    let inventory = try InventoryBuilder(timeZone: zone).scan(paths: roots.map(\.path))
    let differences = try await CalibrationPlanOracleTests.differences(
      oracle, inventory: inventory, scratch: ScratchDirectory.url)
    #expect(differences.isEmpty, "\(differences.joined(separator: "\n"))")
  }
}
