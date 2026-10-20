import Foundation
import StackKit
import TestSupport
import Testing

/// The real-capture cases recorded under `~/Documents/astro/fixtures/oracle` (never committed).
@Suite(
  "Live oracle cases recorded from real captures", .liveFixtures, .tags(.live),
  .timeLimit(.minutes(1)))
struct LiveOracleTests {
  static var home: URL { URL(fileURLWithPath: NSHomeDirectory()) }

  @Test(
    "a recorded real case verifies its hashes and holds the cross-file invariants",
    arguments: ["m31-db", "m31-bb-db"])
  func testLiveOracle_decodes(_ name: String) throws {
    guard let oracle = try OracleLiveCases.find(name, home: Self.home) else {
      try Test.cancel(
        "\(name) not recorded: go run ./cmd/oraclerec --case \(name) in ../stacking-astro")
    }
    try OracleFixtureTests.expectConsistent(oracle)
    #expect(try !oracle.scripts().isEmpty)
    #expect(try oracle.masterHashes().contains { $0.path.contains("master_") })
  }
}
