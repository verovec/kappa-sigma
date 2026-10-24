import Foundation
import StackKit
import TestSupport
import Testing

/// Card 0101 on the real IC 1848 captures: 0058 found two project packages in
/// `captures/IC1848` and the run was refused as « mixed objects ("", "IC 1848") ». The captures
/// stay read-only, so the package is put beside them in the scratch folder, as one more root.
@Suite(
  "Live packages among captures — IC 1848 with a project package plans one object",
  .liveFixtures, .tags(.live), .serialized, .timeLimit(.minutes(10)))
struct LivePackagesInCapturesTests {
  @Test(
    "the package's stacks are skipped and named; the run's object guard passes", .scratchDirectory)
  func testPackageBesideCapturesPlansOneObject() throws {
    let capture = LiveInventoryOracleTests.captures.appendingPathComponent("IC1848")
    let roots = ["lights", "darks", "flats", "bias"].map { capture.appendingPathComponent($0) }
    guard roots.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
      try Test.cancel("IC1848 absent under ~/Documents/astro/captures")
    }
    let beside = try ScratchDirectory.url.appendingPathComponent("IC1848")
    // A run's stack as 0058 found it: no IMAGETYP, no OBJECT.
    try TestFITS.write(
      "test-build.astrostack/stacks/20261021/combined.fits", in: beside, pixel: 1200,
      cards: ["EXPTIME": "120.0"])

    let inventory = try InventoryBuilder().scan(paths: (roots + [beside]).map(\.path))

    let skips = InventoryBuilderTests.skipWarnings(inventory)
    #expect(skips.count == 1)
    #expect(skips.first?.contains("IC1848/test-build.astrostack") == true, "\(skips)")
    let objects = Set(inventory.sets.filter { $0.key.type == .light }.map(\.key.object))
    #expect(objects.count == 1, "one object: \(objects)")
    _ = try Preprocessor.plan(inventory)
  }
}
