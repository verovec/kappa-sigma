import Foundation
import StackKit
import Testing

/// `FilterSetLanes` is `filtersetlanes.go`: cases of `TestPartitionGroups_FilterSet`,
/// `TestPartitionGroups_MonoIsUntouched`, `TestDualbandLast` and
/// `TestOrderedFilters_NonCanonicalIsDeterministic`, through `Preprocessor.plan`.
@Suite("FilterSetLanes — broadband and dual-band exposures stack as two lanes")
struct FilterSetLanesTests {
  static let (nightA, nightB) = ("2026-07-29", "2026-08-02")

  /// A one-shot-colour light set of two frames.
  static func set(_ night: String, exposureMs: Int, filter: String = Filter.color) -> FrameSet {
    let key = SetKey(
      type: .light, object: "NGC7000", filter: filter, exposureMs: exposureMs, gain: 100,
      offset: 50, tempBucketC: -10, bin: 1, session: night)
    return FrameSet(
      key: key,
      frames: (1...2).map { CaptureFrame(path: "/cur/\(night)_\(exposureMs)_\($0).fits") },
      indices: [0, 1])
  }

  /// An OSC scan of `sets` with their verdicts (index-aligned; unknown = unclassified).
  static func scan(_ sets: [FrameSet], _ verdicts: [FilterSet], color: ColorModel = .osc)
    -> Inventory
  {
    var inventory = Inventory(root: "/cur", frames: sets.flatMap(\.frames))
    inventory.colorModel = color
    inventory.sets = sets
    for (set, verdict) in zip(sets, verdicts) where verdict.isKnown {
      inventory.filterSets[set.key.id] = verdict
    }
    return inventory
  }

  static let twoNights = [set(nightA, exposureMs: 120_000), set(nightB, exposureMs: 300_000)]

  @Test(
    "both kinds measured split into RGB + RGB-dualband; anything else keeps one lane",
    arguments: [
      (twoNights, [FilterSet.broadband, .dualband], ["RGB", "RGB-dualband"]),
      (twoNights, [.dualband, .broadband], ["RGB", "RGB-dualband"]),
      ([set(nightA, exposureMs: 120_000)], [.dualband], ["RGB"]),
      ([set(nightA, exposureMs: 120_000)], [.broadband], ["RGB"]),
      (twoNights, [.broadband, .broadband], ["RGB"]),
      (twoNights, [.unknown, .unknown], ["RGB"]),
      (twoNights, [.dualband, .unknown], ["RGB"]),
    ])
  func testPartition(sets: [FrameSet], verdicts: [FilterSet], lanes: [String]) throws {
    let plan = try Preprocessor.plan(Self.scan(sets, verdicts))
    #expect(plan.channels.keys.sorted() == lanes)
    // The lane names the stack; it never renames the light (calibration matches on the key).
    #expect(plan.channels.values.joined().allSatisfy { $0.key.filter == Filter.color })
  }

  @Test("a mono scan keeps its filter lanes")
  func testMonoUntouched() throws {
    let plan = try Preprocessor.plan(
      Self.scan([Self.set(Self.nightA, exposureMs: 1000, filter: "L")], [], color: .mono))
    #expect(plan.channels.keys.sorted() == ["L"] && plan.channels["L"]?.first?.key.filter == "L")
  }

  @Test(
    "the dual-band lane registers last, onto the broadband grid",
    arguments: [
      (["RGB-dualband", "RGB"], ["RGB", "RGB-dualband"]),
      (["RGB", "RGB-dualband"], ["RGB", "RGB-dualband"]),
      (["L", "R", "G", "B"], ["L", "R", "G", "B"]),
      (["RGB"], ["RGB"]),
    ])
  func testDualbandLast(order: [String], expected: [String]) {
    #expect(FilterSetLanes.dualbandLast(order) == expected)
  }

  @Test("lane helpers: base filter, the dual-band lane of a channel map")
  func testLaneNames() {
    #expect(FilterSetLanes.baseFilter(of: "RGB-dualband") == "RGB")
    #expect(FilterSetLanes.baseFilter(of: "RGB") == "RGB")
    #expect(FilterSetLanes.dualbandLane(in: ["RGB", "RGB-dualband"]) == "RGB-dualband")
    #expect(FilterSetLanes.dualbandLane(in: ["L", "R"]) == nil)
  }

  @Test("non-canonical lanes sort deterministically after the canonical filters")
  func testOrderedDeterministic() {
    #expect(ChannelAligner.ordered(["L", "RGB-dualband", "RGB", "Zz"]) == ["L", "RGB", "RGB-dualband", "Zz"])
  }
}
