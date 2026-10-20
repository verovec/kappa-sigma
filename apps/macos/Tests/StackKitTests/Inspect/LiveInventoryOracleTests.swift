import Foundation
import StackKit
import TestSupport
import Testing

/// The inspect port against the recorded inventories, on the real frames under
/// `~/Documents/astro` (pixels read, so OSC filter sets and the CFA probe are exercised).
@Suite(
  "Live inventory oracle — real frames and captures", .liveFixtures, .tags(.live), .serialized,
  .timeLimit(.minutes(5)))
struct LiveInventoryOracleTests {
  static var home: URL { URL(fileURLWithPath: NSHomeDirectory()) }
  static var captures: URL { home.appendingPathComponent("Documents/astro/captures") }

  static func liveCase(_ name: String) throws -> OracleCase {
    guard let oracle = try OracleLiveCases.find(name, home: home) else {
      try Test.cancel("\(name) not recorded under ~/Documents/astro/fixtures/oracle")
    }
    return oracle
  }

  @Test(
    "the committed header fixture is the recorded in/ folder (RECORD=1 rewrites it)",
    arguments: ["golden-single-night", "golden-two-night"])
  func testLiveInventoryOracle_headerFixture(name: String) throws {
    let input = try Self.liveCase(name).directory.deletingLastPathComponent()
      .appendingPathComponent("in")
    let live = try HeaderFixture.read(root: input)
    if ProcessInfo.processInfo.environment["RECORD"] == "1" {
      try live.write(to: HeaderFixture.sourceURL(name))
    }
    #expect(try live == HeaderFixture.load(name))
  }

  @Test(
    "the synthetic cases' real in/ frames give the recorded inventory",
    arguments: ["golden-single-night", "golden-two-night"])
  func testLiveInventoryOracle_synthetic(name: String) throws {
    let oracle = try Self.liveCase(name)
    let root = oracle.directory.deletingLastPathComponent()
    let differences = try InventoryOracleTests.differences(
      oracle, roots: [root.appendingPathComponent("in")], replacing: [(root.path, "<ROOT>")])
    #expect(differences.isEmpty, "\(differences.joined(separator: "\n"))")
  }

  @Test(
    "the M31 captures give the recorded inventory (OSC, filter sets, nights)",
    arguments: [("m31-db", ["M31-DB"]), ("m31-bb-db", ["M31-DB", "M31-BB"])])
  func testLiveInventoryOracle_captures(name: String, captures: [String]) throws {
    let oracle = try Self.liveCase(name)
    let roots = captures.flatMap { capture in
      ["lights", "darks", "flats", "bias"].map {
        Self.captures.appendingPathComponent(capture).appendingPathComponent($0)
      }
    }
    guard roots.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
      try Test.cancel("captures \(captures) absent under ~/Documents/astro/captures")
    }
    let differences = try InventoryOracleTests.differences(
      oracle, roots: roots, replacing: [(Self.captures.path, "<CAPTURES>")])
    #expect(differences.isEmpty, "\(differences.joined(separator: "\n"))")
  }
}
