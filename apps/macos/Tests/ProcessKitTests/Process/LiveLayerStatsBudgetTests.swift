import Foundation
import ImageKit
import ProcessKit
import TestSupport
import Testing

/// Card 0187: 26 Mpx × 3 planes, the PO's stacks, measured in the budget of the build — the lazy
/// formula took ~19 s a plane unoptimised (`just app-run` is unoptimised), 84 ms the three
/// optimised. A budget is local only (`Live`: skipped by `just test-unit`, never on CI).
@Suite(
  "Live LayerStats.measured — 26 Mpx within budget",
  .enabled(if: ProcessInfo.processInfo.environment["ASTROSTACK_SKIP_LIVE"] != "1"),
  .tags(.live), .timeLimit(.minutes(2)))
struct LiveLayerStatsBudgetTests {
  @Test("testMeasured_26MpxWithinBudget")
  func testMeasured_26MpxWithinBudget() {
    let (width, height) = (6248, 4176)
    var plane = [Float](repeating: 0, count: width * height)
    for index in stride(from: 0, to: plane.count, by: 7) {
      plane[index] = Float(index % 4096) / 4096
    }
    plane[12_345] = .nan
    let image = AstroImage(
      width: width, height: height, planes: [plane, plane, plane],
      metadata: ImageMetadata(rowOrder: .topDown))

    let clock = ContinuousClock()
    let elapsed = clock.measure { _ = LayerStats.measured(image) }

    let budget: Duration = BuildConfiguration.optimized ? .milliseconds(400) : .seconds(5)
    #expect(elapsed < budget, "\(elapsed)")
  }
}
