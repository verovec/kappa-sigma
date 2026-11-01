import Foundation
import StackKit
import TestSupport
import Testing

/// Card 0173: the two-night LRGB run whose G and B lanes fail still ends on L alone, and now warns
/// that the colour composite it planned is gone (the per-lane failures keep their own warnings).
extension PreprocessTwoNightOracleTests {
  @Test("a colour run left with L alone warns that its combined image is grey", .scratchDirectory)
  func testLostChannelsWarnGreyCombined() async throws {
    let oracle = try OracleFixtureTests.committedCase("golden-two-night")
    let root = try InventoryBuilderFallbackTests.folder("scan")
    // The 2024-03-01 night carries G and B alone: its calibration failing loses both channels.
    let (_, result) = try await PreprocessOracleTests.run(
      root: root, oracle: oracle, edge: Self.fullField,
      fails: {
        $0.contains("seqsubsky")
          || $0.contains("calibrate light -dark=") && $0.contains("DARK_10000ms")
      })
    #expect(result.combinedPath?.hasSuffix("/combined.fits") == true)
    // The warning replaces the mono note: the loss is not « no colour composite to build ».
    #expect(!result.notes.contains { $0.hasPrefix("combined = ") })
    #expect(
      result.warnings.filter { $0.hasPrefix("no colour composite") } == [
        "no colour composite: G, B missing — combined = L alone, in grey"
      ])
  }
}
