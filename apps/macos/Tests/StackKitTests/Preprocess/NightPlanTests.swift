import Foundation
import StackKit
import TestSupport
import Testing

/// `NightPlan` is `ReusePlan.computeAnchor` + `anchorGroupIndex` (`reuse_night_test.go`
/// `TestAnchorGroupIndex`; the "prior session vs current capture" case does not apply: this app
/// only stacks its own capture), and the anchor night of case (b) as recorded.
@Suite("NightPlan — groups per channel, the anchor night and each channel's anchor group")
struct NightPlanTests {
  static func group(_ night: String, _ filter: String, frames: Int) -> FrameSet {
    let key = SetKey(
      type: .light, object: "T", filter: filter, exposureMs: 1000, gain: 100, offset: 10,
      tempBucketC: -10, bin: 1, session: night)
    return FrameSet(
      key: key, frames: (0..<frames).map { CaptureFrame(path: "/\(night)/\(filter)_\($0).fits") },
      indices: Array(0..<frames))
  }

  @Test(
    "a channel's anchor group: anchor night, then frames, then the later night",
    arguments: [
      ([("2020-04-26", 300), ("2023-02-27", 30)], "2023-02-27", 1),
      ([("2023-02-27", 10), ("2023-02-27", 90)], "2023-02-27", 1),
      ([("2020-04-26", 100)], "2023-02-27", 0),
      ([("2020-04-26", 40), ("2021-01-01", 40)], "2023-02-27", 1),
    ])
  func testAnchorGroup(groups: [(String, Int)], night: String, want: Int) {
    let sets = groups.map { Self.group($0.0, "L", frames: $0.1) }
    #expect(NightPlan.anchorGroup(sets, anchorNight: night) == want)
  }

  @Test("the anchor night covers the most channels; one group per channel is not anchored")
  func testAnchorNight() {
    let plan = NightPlan([
      Self.group("2020-05-15", "L", frames: 2), Self.group("2024-03-01", "L", frames: 3),
      Self.group("2024-03-01", "G", frames: 3), Self.group("2024-03-01", "B", frames: 1),
      Self.group("2020-05-15", "R", frames: 9),
    ])
    #expect(plan.anchored && plan.anchorNight == "2024-03-01")
    #expect(plan.nights == ["2020-05-15", "2024-03-01"])
    #expect(plan.channels["L"]?.map(\.key.session) == ["2020-05-15", "2024-03-01"])
    let single = NightPlan([
      Self.group("2020-05-15", "L", frames: 2), Self.group("2020-05-15", "R", frames: 2),
    ])
    #expect(!single.anchored && single.anchorNight.isEmpty)
  }

  @Test("case (b): L and R span two nights, anchored on 2024-03-01 as recorded", .scratchDirectory)
  func testGoldenTwoNight() throws {
    let root = try InventoryBuilderFallbackTests.folder("scan")
    let inventory = try MasterBuilderTests.scan("golden-two-night", under: root)
    let plan = NightPlan(inventory.sets.filter { $0.key.type == .light })
    let recorded = try OracleFixtureTests.committedCase("golden-two-night").run()
    #expect(plan.anchored && plan.anchorNight == (recorded.anchorNight ?? ""))
    #expect(plan.channels["L"]?.count == 2 && plan.channels["R"]?.count == 2)
    #expect(plan.channels["G"]?.count == 1 && plan.channels["B"]?.count == 1)
  }
}
