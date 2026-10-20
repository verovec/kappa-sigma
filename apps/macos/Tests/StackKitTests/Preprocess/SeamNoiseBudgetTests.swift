import Foundation
import ImageKit
import StackKit
import TestSupport
import Testing

/// The seam noise pass's memory gate (`seamnoise.go:76`): a master needing W·H·4·10 bytes over
/// the budget is skipped, untouched, with the reason.
@Suite("SeamNoiseEqualiser budget — skipped, not exhausted, above the memory budget")
struct SeamNoiseBudgetTests {
  @Test("over the budget: untouched and the reason says so", .scratchDirectory)
  func testOverBudget() throws {
    let plane = (0..<(64 * 64)).map { Float($0 % 7) * 0.01 }
    let url = try FloatFITS.write(
      try ScratchDirectory.url.appendingPathComponent("master.fits"), width: 64, height: 64,
      planes: [plane])
    let record = SeamNoiseEqualiser.equalise(
      url, grid: CoverageGrid(canvasWidth: 64, canvasHeight: 64), budget: 64 * 64 * 4 * 10 - 1)
    #expect(
      !record.applied && record.overBudget
        && record.reason == "skipped: needs ~0 MB, over the memory budget")
    #expect(try FITSFile.read(at: url).image().planes[0] == plane)
  }
}
