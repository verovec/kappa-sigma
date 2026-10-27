import FilterKit
import Foundation
import StackKit
import TestSupport
import Testing

/// Card 0121: a split run's lane may carry its own lane-scoped knobs. The override reaches that
/// lane's stacker only; the other lane, the shared canvas and an unsplit run never see it.
extension PreprocessorTests {
  /// The golden single night reduced to L (measured broadband) and R (measured dual-band): a
  /// split run of two lanes, `L` and `R-dualband`.
  static func splitRequest(_ run: String) throws -> PreprocessRequest {
    let root = try InventoryBuilderFallbackTests.folder("scan")
    var inventory = try MasterBuilderTests.scan("golden-single-night", under: root)
    inventory.sets.removeAll { $0.key.type == .light && !["L", "R"].contains($0.key.filter) }
    for set in inventory.sets where set.key.type == .light {
      inventory.filterSets[set.key.id] = set.key.filter == "L" ? .broadband : .dualband
    }
    return PreprocessRequest(
      inventory: inventory, output: root.appendingPathComponent("out/TESTFIELD/\(run)"),
      work: root.appendingPathComponent("work/run_\(run)"), runID: run,
      settings: .recorded)
  }

  /// The stack scripts of a run of `request`, by the lane folder they stack in, its run id out.
  static func stackScripts(_ request: PreprocessRequest) async throws -> [String: String] {
    let siril = PipelineSiril()
    _ = await collect(Preprocessor(tools: tools(siril)).run(request))
    var scripts: [String: String] = [:]
    for call in siril.calls where call.script.contains("stack r_pp_light_") {
      // The run id names the output folder: the same script otherwise.
      scripts[call.directory.lastPathComponent] = call.script.replacingOccurrences(
        of: "/\(request.runID)/", with: "/RUN/")
    }
    return scripts
  }

  @Test("a dual-band rejection override changes the dual-band lane's stack only", .scratchDirectory)
  func testLaneOverrideReachesOnlyItsLane() async throws {
    let plain = try await Self.stackScripts(try Self.splitRequest("PLAIN"))
    var request = try Self.splitRequest("LANE")
    try request.overrideLane(
      .dualband,
      with: KnobPatch(values: [
        "stack_reject": .choice("sigma"), "stack_reject_low": .number(2.5),
        "stack_reject_high": .number(2.5),
      ]))
    let overridden = try await Self.stackScripts(request)
    #expect(plain.count == 2 && Set(plain.keys) == Set(overridden.keys))
    let broadband = try #require(plain.keys.first { !$0.contains("dualband") })
    let dualband = try #require(plain.keys.first { $0.contains("dualband") })
    #expect(overridden[broadband] == plain[broadband], "the broadband lane byte-identical")
    #expect(overridden[dualband] != plain[dualband])
    #expect(
      overridden[dualband]?.contains(" sigma 2.5 2.5") == true, "\(overridden[dualband] ?? "")")
  }

  @Test(
    "lane settings: an override applies only in a split run, only to its kind of lane",
    .scratchDirectory)
  func testLaneSettingsResolution() throws {
    var request = try Self.splitRequest("RESOLVE")
    let split = try Preprocessor.plan(request.inventory)
    #expect(Set(split.channels.keys) == ["L", "R-dualband"])
    // No override: every lane stacks with the run's settings, exactly.
    for lane in split.channels.keys {
      #expect(request.settings(forLane: lane, in: split) == request.settings)
    }
    try request.overrideLane(.broadband, with: KnobPatch(values: ["trail_mask_k": .number(2)]))
    #expect(request.settings(forLane: "L", in: split).trailMaskK == 2)
    #expect(request.settings(forLane: "R-dualband", in: split) == request.settings)
    // An unsplit run has no broadband lane: its plain-filter lanes never take the override.
    var unsplit = try Self.request("UNSPLIT")
    try unsplit.overrideLane(.broadband, with: KnobPatch(values: ["trail_mask_k": .number(2)]))
    let plan = try Preprocessor.plan(unsplit.inventory)
    for lane in plan.channels.keys {
      #expect(unsplit.settings(forLane: lane, in: plan) == unsplit.settings, "\(lane)")
    }
  }

  @Test("a lane override of a run-wide knob is refused, nothing recorded", .scratchDirectory)
  func testRunWideOverrideRefused() throws {
    var request = try Self.splitRequest("REFUSED")
    #expect(throws: KnobError.runWide("register_2pass")) {
      try request.overrideLane(.dualband, with: KnobPatch(values: ["register_2pass": .flag(true)]))
    }
    #expect(request.laneOverrides.isEmpty)
  }

  @Test(
    "overrides on an unsplit run: scripts equal the recorded case byte for byte",
    .scratchDirectory)
  func testNoOverrideIsByteIdentical() async throws {
    let oracle = try OracleFixtureTests.committedCase("golden-single-night")
    let root = try InventoryBuilderFallbackTests.folder("scan")
    let inventory = try MasterBuilderTests.scan("golden-single-night", under: root)
    let playback = PreprocessOracleTests.Playback(try oracle.grades())
    let siril = PipelineSiril(sequence: { playback.sequences[$0] })
    let tools = Preprocessor.Tools(
      runner: siril.runner, trailProbe: { frame, _ in playback.trail(frame) },
      edgeMeasure: { _ in PreprocessOracleTests.cappedEdge })
    var request = PreprocessRequest(
      inventory: inventory,
      output: root.appendingPathComponent("out/TESTFIELD/\(PreprocessOracleTests.runID)"),
      work: root.appendingPathComponent("work/run_\(PreprocessOracleTests.runID)"),
      runID: PreprocessOracleTests.runID, settings: .recorded)
    let patch = KnobPatch(values: ["stack_reject": .choice("sigma"), "fwhm_sigma": .number(1.5)])
    try request.overrideLane(.broadband, with: patch)
    try request.overrideLane(.dualband, with: patch)
    let (_, error) = await Self.collect(Preprocessor(tools: tools).run(request))
    #expect(error == nil)
    let recorded = try oracle.scripts().filter { $0.number <= 18 }
    let ours = siril.calls.map { PreprocessOracleTests.normalize($0.script, root: root) }
    #expect(ours.count >= recorded.count)
    for (index, script) in recorded.enumerated() where index < ours.count {
      #expect(ours[index] == script.text, "script \(script.name)")
    }
  }

  @Test(
    "a resume after a dual-band override reuses the broadband lane, re-runs the dual-band one",
    .scratchDirectory)
  func testLaneOverrideStalesOnlyItsLane() throws {
    var request = try Self.splitRequest("RESUME")
    let plan = try Preprocessor.plan(request.inventory)
    let records = try plan.channels.mapValues { groups in
      let set = try #require(groups.first)
      return ChannelOutcome(set, filter: set.key.filter, selection: CalibrationSelection())
    }
    let checkpoints = records.map { lane, outcome in
      (lane, LaneRecord(outcome, lane: lane, plan: plan, request: request))
    }
    try request.overrideLane(.dualband, with: KnobPatch(values: ["fwhm_sigma": .number(2)]))
    for (lane, record) in checkpoints {
      let reason = record.staleReason(lane: lane, plan: plan, request: request)
      #expect(reason == (lane == "L" ? nil : "the settings changed"), "\(lane)")
    }
  }

  @Test(
    "an SII+OIII clip's lane takes its own kind of override, the dual-band one stays apart",
    .scratchDirectory)
  func testLaneKindBySet() throws {
    var request = try Self.splitRequest("KIND")
    for set in request.inventory.sets where set.key.type == .light && set.key.filter == "R" {
      request.inventory.filterSets[set.key.id] = .dualbandSII
    }
    let split = try Preprocessor.plan(request.inventory)
    #expect(Set(split.channels.keys) == ["L", "R-dualband-sii"])
    try request.overrideLane(.dualbandSII, with: KnobPatch(values: ["trail_mask_k": .number(2)]))
    try request.overrideLane(.dualband, with: KnobPatch(values: ["trail_mask_k": .number(5)]))
    #expect(request.settings(forLane: "R-dualband-sii", in: split).trailMaskK == 2)
    #expect(request.settings(forLane: "L", in: split) == request.settings)
  }
}
