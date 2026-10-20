import Foundation
import StackKit
import TestSupport
import Testing

/// The real calibration library under `~/Documents/astro/library`: every kind of master reads,
/// measures on Siril's normalised scale, and a healthy flat has darker corners.
@Suite(
  "Live master inspection — the real library", .liveFixtures, .tags(.live), .serialized,
  .timeLimit(.minutes(5)))
struct LiveMasterInspectTests {
  static let library = URL(fileURLWithPath: NSHomeDirectory())
    .appendingPathComponent("Documents/astro/library")

  @Test(
    "the M31-DB masters read with their stats",
    arguments: [
      "master_BIAS_g100o50_b1.fits", "master_DARK_300000ms_g100o50_b1_-19C.fits",
      "master_FLAT_15000ms_g100o50_b1_0C.fits",
    ])
  func testLiveMasterInspection(name: String) throws {
    let path = Self.library.appendingPathComponent(name).path
    guard FileManager.default.fileExists(atPath: path) else {
      try Test.cancel("\(name) absent from the library")
    }
    let inspection = try MasterInspection.read(path)
    #expect(inspection.width == 6248 && inspection.height == 4176)
    #expect(inspection.frames > 0, "the .sig says how many frames")
    #expect(inspection.stats.fullScale == 1, "Siril writes normalised float masters")
    #expect(inspection.stats.median > 0 && inspection.stats.median < 1)
    if inspection.master.type == .flat {
      #expect(try #require(inspection.stats.vignettingPct) < 0, "a healthy flat")
    }
    Attachment.record(
      "\(name): \(inspection.stats) \(inspection.warnings.map(\.message))", named: "\(name).txt")
  }

  @Test("a file that is not a master is refused by name")
  func testNotAMaster() {
    #expect(throws: CalibrationError.notAMaster("/tmp/light_001.fits")) {
      try MasterInspection.read("/tmp/light_001.fits")
    }
  }
}
