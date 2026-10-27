import AstroStackApp
import FilterKit
import Foundation
import StackKit
import Testing

/// Card 0121: when the checked series split into broadband and dual-band lanes, the panel offers a
/// column per lane for the lane-scoped knobs and the processing choice; otherwise neither, and a
/// run records no lane override.
extension KnobPanelViewModelTests {
  struct Split: Sendable, CustomTestStringConvertible {
    let name: String
    /// The clip filter of each night's set, in night order.
    let verdicts: [FilterSet]
    let columns: [FilterSet]
    var testDescription: String { name }
  }

  /// One object over two nights, each night's set measured as `verdicts` says.
  nonisolated static func inventory(_ verdicts: [FilterSet]) -> Inventory {
    let nights = ["2026-09-21", "2026-09-22"]
    var inventory = StackingStageModelTests.inventory(objects: ["M 31"], nights: nights)
    inventory.colorModel = .osc
    for set in inventory.sets where set.key.type == .light {
      let index = nights.firstIndex(of: set.key.session) ?? 0
      inventory.filterSets[set.key.id] = verdicts[index]
    }
    return inventory
  }

  /// The series of `inventory(verdicts)`, every set checked.
  static func series(_ verdicts: [FilterSet]) -> StackingStageModel {
    StackingStageModel(inventory: inventory(verdicts))
  }

  @Test(
    "lane columns only when the checked series split",
    arguments: [
      Split(name: "BB only", verdicts: [.broadband, .broadband], columns: []),
      Split(name: "DB only", verdicts: [.dualband, .dualband], columns: []),
      Split(name: "BB+DB", verdicts: [.broadband, .dualband], columns: [.broadband, .dualband]),
      // The engine splits only on a measured broadband AND a measured dual-band set.
      Split(name: "unclassified+DB", verdicts: [.unknown, .dualband], columns: []),
    ])
  func testLaneColumnsOnlyWhenSplit(_ split: Split) throws {
    let series = Self.series(split.verdicts)
    #expect(series.laneColumns == split.columns)
    let scope = try #require(series.scopes.first)
    #expect(series.splits(scope) == !split.columns.isEmpty)
  }

  @Test("unchecking the dual-band night drops the columns: the run no longer splits")
  func testUncheckedLaneDropsColumns() throws {
    let series = Self.series([.broadband, .dualband])
    let dualband = try #require(
      series.groups.flatMap(\.nights).flatMap(\.series).first { $0.filterSet == .dualband })
    series.set(dualband.id, checked: false)
    #expect(series.laneColumns.isEmpty)
    #expect(series.splits(try #require(series.scopes.first)) == false)
  }

  @Test("a lane edit is badged against the global value, leaves the other lane, and resets")
  func testLaneEditAndReset() throws {
    let panel = KnobPanelViewModel(mode: .deepsky)
    panel.set("stack_reject", to: .choice("sigma"), lane: .dualband)
    let lane = try #require(panel.rows(lane: .dualband).first { $0.id == "stack_reject" })
    #expect(lane.value == .choice("sigma") && !lane.isDefault, "≠ global")
    #expect(panel.rows(lane: .broadband).allSatisfy { $0.isDefault })
    #expect(panel.rows.allSatisfy { $0.isDefault }, "the global values untouched")
    #expect(panel.overrideCount(lane: .dualband) == 1)
    #expect(panel.overrideCount(lane: .broadband) == 0)
    panel.reset("stack_reject", lane: .dualband)
    #expect(panel.rows(lane: .dualband).allSatisfy { $0.isDefault })
    #expect(panel.overrideCount(lane: .dualband) == 0)
  }

  @Test("a run-wide knob never takes a lane value: its lane row shows the global one")
  func testRunWideKnobRefusesLaneEdit() throws {
    let panel = KnobPanelViewModel(mode: .deepsky)
    panel.set("register_2pass", to: .flag(true), lane: .dualband)
    #expect(panel.overrideCount(lane: .dualband) == 0)
    panel.set("register_2pass", to: .flag(true))
    let row = try #require(panel.rows(lane: .dualband).first { $0.id == "register_2pass" })
    #expect(row.value == .flag(true) && row.isDefault, "the global value, not an override")
    #expect(row.scope == .run(.registration))
  }

  @Test("the run knobs: lane overrides and the processing choice; an unsplit run drops both")
  func testRunKnobsOnlyWhenSplit() {
    let panel = KnobPanelViewModel(mode: .deepsky)
    panel.set("fwhm_sigma", to: .number(2))
    panel.set("stack_reject", to: .choice("sigma"), lane: .dualband)
    // A lane value equal to the global one is no override.
    panel.set("fwhm_sigma", to: .number(2), lane: .broadband)
    panel.processing = .perChannel
    let split = panel.runKnobs(for: .deepsky)
    #expect(split.patch == KnobPatch(values: ["fwhm_sigma": .number(2)]))
    #expect(split.lanes == [.dualband: KnobPatch(values: ["stack_reject": .choice("sigma")])])
    #expect(split.processing == .perChannel)
    let unsplit = split.unsplit
    #expect(unsplit.patch == split.patch && unsplit.lanes.isEmpty && unsplit.processing == .single)
  }

  @Test(
    "a recorded run loads its lane values and processing back; a run-wide lane entry is ignored")
  func testLoadRecordedLanes() throws {
    var record = StackRecord(request: ImportRequest(paths: ["/c/M31"]))
    record.laneKnobs = [
      .dualband: KnobPatch(values: ["stack_reject": .choice("sigma"), "edge_crop": .flag(false)])
    ]
    record.processing = .perChannel
    let panel = KnobPanelViewModel(mode: .deepsky)
    panel.load(record)
    let row = try #require(panel.rows(lane: .dualband).first { $0.id == "stack_reject" })
    #expect(row.value == .choice("sigma"))
    #expect(panel.processing == .perChannel)
    #expect(panel.ignored == ["lane_knobs.dualband.edge_crop"])
  }

  @Test(
    "a run-wide knob's help says why every lane shares it, in fr and en", arguments: ["fr", "en"])
  func testSharedWhyInHelp(language: String) {
    let locale = Locale(identifier: language)
    let panel = KnobPanelViewModel(mode: .deepsky)
    let why = String(localized: KnobPanelViewModel.sharedWords(.registration, locale: locale))
    #expect(why.hasPrefix(language == "fr" ? "Commun à toutes les voies" : "Shared by every lane:"))
    #expect(panel.help(for: "register_2pass", locale: locale).hasSuffix(" " + why))
    #expect(!panel.help(for: "fwhm_sigma", locale: locale).contains(why), "a lane knob: no why")
  }

  @Test("a lane value set to the global one clears the edit: a later global move overrides nothing")
  func testLaneValueAtGlobalIsNoPin() {
    let panel = KnobPanelViewModel(mode: .deepsky)
    panel.set("fwhm_sigma", to: .number(2))
    panel.set("fwhm_sigma", to: .number(3), lane: .dualband)
    panel.set("fwhm_sigma", to: .number(2), lane: .dualband)
    panel.set("fwhm_sigma", to: .number(3))
    #expect(panel.overrideCount(lane: .dualband) == 0)
    #expect(panel.runKnobs(for: .deepsky).lanes.isEmpty)
  }

  @Test("a lane value stays as set while the global value moves through it")
  func testGlobalMoveKeepsLaneValue() {
    let panel = KnobPanelViewModel(mode: .deepsky)
    panel.set("trail_mask_k", to: .number(2))
    panel.set("trail_mask_k", to: .number(4), lane: .dualband)
    for step in [3.0, 4, 5, 6] { panel.set("trail_mask_k", to: .number(step)) }
    #expect(panel.overrideCount(lane: .dualband) == 1)
    #expect(panel.runKnobs(for: .deepsky).lanes[.dualband]?.values["trail_mask_k"] == .number(4))
  }

  @Test("Reset All brings the processing back to one flow too")
  func testResetAllResetsProcessing() {
    let panel = KnobPanelViewModel(mode: .deepsky)
    panel.processing = .perChannel
    panel.set("fwhm_sigma", to: .number(2), lane: .dualband)
    panel.resetAll()
    #expect(panel.processing == .single && panel.overrideCount(lane: .dualband) == 0)
  }
}
