import AstroStackApp
import Foundation
import Metal
import ProcessKit
import ProjectKit
import RenderKit
import TestSupport
import Testing

/// The Studio's pipeline column (card 0088): Run halts at a breakpoint with its recipe in the
/// panel, Continue applies the panel's values, a manual Apply becomes a step, a replay reuses
/// locked steps, pipelines are saved and loaded in the project.
@MainActor
@Suite(
  "Pipeline sidebar — run, breakpoint, Continue, manual steps, replay, save and load",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
struct PipelineSidebarModelTests {
  static func step(
    _ type: any ImageProcess.Type, _ values: [String: ParamValue] = [:],
    _ mode: PipelineStep.Mode = .auto, locked: Bool = false
  ) throws -> PipelineStep {
    var params = ParamSet(schema: type.schema)
    for (id, value) in values { try params.set(id, value) }
    return PipelineStep(
      recipe: Recipe(processID: type.id, params: params), mode: mode, locked: locked)
  }

  static func sidebar(_ opened: StudioModelTests.Opened, _ pipeline: Pipeline) throws
    -> (StudioWorkspaceModel, PipelineSidebarModel)
  {
    let workspace = try StudioWorkspaceModelTests.workspace(
      opened, bundle: StudioModelTests.bundle())
    let sidebar = try PipelineSidebarModel(
      workspace: workspace, pipeline: pipeline, store: opened.package.store, base: [.color])
    workspace.pipeline = sidebar
    return (workspace, sidebar)
  }

  @Test(
    "Run halts at the breakpoint with its recipe; Continue applies the panel's values",
    .scratchDirectory)
  func testRunStopsAndLoadsPanel() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let pipeline = Pipeline(
      name: "p",
      steps: [
        try Self.step(ChannelCombinationProcess.self),
        try Self.step(StretchProcess.self, ["targetBackground": .number(0.2)]),
        try Self.step(CurvesProcess.self, [:], .stop),
        try Self.step(SaturationProcess.self),
      ])
    let (workspace, sidebar) = try Self.sidebar(opened, pipeline)
    #expect(sidebar.status(of: 0) == .done && sidebar.status(of: 1) == .next)

    await sidebar.run()
    #expect(sidebar.failure == nil)
    #expect(workspace.studio.steps.map(\.processID) == ["channel-combination", "stretch"])
    #expect(sidebar.stoppedAt == 2 && sidebar.status(of: 2) == .current)
    #expect(sidebar.events == [.applied(1), .stopped(2)])
    let panel = try #require(workspace.panel)
    #expect(panel.type.id == CurvesProcess.id)

    let edited = CurvePoint(0.5, 0.6)
    panel.set("rgb", .points([CurvePoint(0, 0), edited, CurvePoint(1, 1)]))
    await sidebar.continueRun()
    #expect(sidebar.failure == nil && sidebar.stoppedAt == nil)
    #expect(
      workspace.studio.steps.map(\.processID)
        == ["channel-combination", "stretch", "curves", "saturation"])
    let curves = workspace.studio.steps[2].params
    #expect(curves.points("rgb").contains(edited), "Continue applied the edited values")
    #expect(
      ParamSet.loading(sidebar.pipeline.steps[2].recipe.params, onto: CurvesProcess.schema)
        .params.points("rgb").contains(edited), "the pipeline keeps them")
    #expect((0..<4).allSatisfy { sidebar.status(of: $0) == .done })
  }

  @Test("an Apply outside the pipeline adds an auto step after the current one", .scratchDirectory)
  func testManualApplyAppendsStep() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let pipeline = Pipeline(
      name: "p",
      steps: [try Self.step(ChannelCombinationProcess.self), try Self.step(StretchProcess.self)])
    let (workspace, sidebar) = try Self.sidebar(opened, pipeline)
    await sidebar.run()
    workspace.choose(SaturationProcess.id)
    await workspace.previewNow()
    try workspace.apply()
    #expect(
      sidebar.pipeline.steps.map(\.recipe.processID)
        == ["channel-combination", "stretch", "saturation"])
    #expect(sidebar.pipeline.steps[2].mode == .auto && !sidebar.pipeline.steps[2].locked)
    #expect(sidebar.status(of: 2) == .done)
  }

  @Test(
    "a locked step keeps its output on replay from the same bundle; the others re-run",
    .scratchDirectory)
  func testLockedStepReusedOnReplay() async throws {
    let first = try StudioModelTests.project()
    defer { try? first.package.close() }
    let pipeline = Pipeline(
      name: "p",
      steps: [
        try Self.step(ChannelCombinationProcess.self),
        try Self.step(StretchProcess.self, locked: true),
        try Self.step(
          CurvesProcess.self,
          ["rgb": .points([CurvePoint(0, 0), CurvePoint(0.4, 0.6), CurvePoint(1, 1)])]),
      ])
    let (one, ran) = try Self.sidebar(first, pipeline)
    await ran.run()
    #expect(ran.events == [.applied(1), .applied(2)])

    let stack = try first.package.store.addStack(
      bundlePath: "stacks/run2", sourceIDs: [], paramsJSON: "{}", imageRoles: ["RGB"])
    let second = StudioModelTests.Opened(
      package: first.package, stackID: stack.id,
      folder: first.package.url.appendingPathComponent("stacks/run2"))
    let (two, replayed) = try Self.sidebar(second, Pipeline(name: "empty", steps: []))
    replayed.show(ran.pipeline)
    await replayed.run(previous: ran.lastRun)
    #expect(replayed.events == [.reused(1), .applied(2)])
    let stretched = { (workspace: StudioWorkspaceModel) in
      try workspace.studio.session.history.output(ofStep: 1).planes
    }
    #expect(try stretched(two) == stretched(one), "the locked stretch is the same output")
  }

  @Test("save then load round-trips; an unknown key is a warning", .scratchDirectory)
  func testReplayMenuListsStacksAndSaveLoad() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let pipeline = Pipeline(
      name: "p",
      steps: [
        try Self.step(ChannelCombinationProcess.self),
        try Self.step(StretchProcess.self, [:], .stop),
      ])
    let (_, sidebar) = try Self.sidebar(opened, pipeline)
    sidebar.save(as: "IC 1848 doux")
    #expect(sidebar.savedNames == ["IC 1848 doux"] && sidebar.pipeline.name == "IC 1848 doux")
    sidebar.setLocked(true, of: 1)
    #expect(
      try sidebar.differences(from: "IC 1848 doux") == [
        PipelineDiff.Entry(step: 1, processID: "stretch", change: .locked(false, true))
      ])
    sidebar.load("IC 1848 doux")
    #expect(sidebar.pipeline.steps.map(\.locked) == [false, false] && sidebar.warnings.isEmpty)

    var object = try #require(
      JSONSerialization.jsonObject(with: sidebar.pipeline.json()) as? [String: Any])
    object["colour"] = "red"
    try opened.package.store.savePipeline(
      named: "edited", json: JSONSerialization.data(withJSONObject: object))
    sidebar.load("edited")
    #expect(sidebar.warnings == ["unknown key colour ignored"])
  }
}

extension PipelineSidebarModelTests {
  @Test(
    "the column, the compare sheet and the replay chooser report their controls", .scratchDirectory)
  func testViews() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let pipeline = Pipeline(
      name: "p",
      steps: [
        try Self.step(ChannelCombinationProcess.self),
        try Self.step(StretchProcess.self, [:], .stop, locked: true),
        try Self.step(StarRecompositionProcess.self),
      ])
    let (_, sidebar) = try Self.sidebar(opened, pipeline)
    await sidebar.run()
    sidebar.save(as: "saved")
    sidebar.setMode(.auto, of: 1)
    for language in ["fr", "en"] {
      let entries = AccessibilityAuditTests.entries(
        PipelineSidebarView(model: sidebar), language: language)
      let ids = Set(entries.map(\.id))
      for id in ["run", "continue", "replay", "files", "step.1.mode", "step.2.lock"] {
        #expect(ids.contains("fr.astrostack.stage.studio.pipeline.\(id)"), "\(id): \(ids)")
      }
      #expect(AccessibilityAudit.problems(entries) == [])
      #expect(sidebar.stepProblems[2].count == 1, "star recomposition needs a starless layer")
    }
    #expect(try sidebar.differences(from: "saved").count == 1)
    sidebar.setLocked(false, of: 1)
    var edited = sidebar.pipeline
    edited.steps[1].recipe = try Self.step(StretchProcess.self, ["targetBackground": .number(0.2)])
      .recipe
    sidebar.show(edited)
    let sheet = AccessibilityAuditTests.entries(
      PipelineDiffSheet(model: sidebar, savedName: "saved") {}, language: "en")
    #expect(!sheet.isEmpty)
    let window = ProjectWindowModel(
      store: { opened.package.store }, planning: { _ in ImportPlanningStub.empty })
    let chooser = AccessibilityAuditTests.entries(ReplayChooser(model: window))
    #expect(chooser.map(\.id).contains("fr.astrostack.stage.studio.pipeline.replay.cancel"))
    for saved in ["saved", "missing"] {
      for language in ["fr", "en"] {
        let sheet = AccessibilityAuditTests.entries(
          PipelineDiffSheet(model: sidebar, savedName: saved) {}, language: language)
        #expect(sheet.map(\.id) == ["fr.astrostack.stage.studio.pipeline.compare.close"])
      }
    }
  }
}

extension PipelineSidebarModelTests {
  @Test(
    "applying the next planned process by hand is that step; save keeps the breakpoint",
    .scratchDirectory)
  func testPlannedStepByHandAndSaveKeepsStop() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let pipeline = Pipeline(
      name: "p",
      steps: [
        try Self.step(ChannelCombinationProcess.self), try Self.step(StretchProcess.self),
        try Self.step(CurvesProcess.self, [:], .stop),
      ])
    let (workspace, sidebar) = try Self.sidebar(opened, pipeline)
    workspace.choose(StretchProcess.id)
    workspace.panel?.set("targetBackground", .number(0.3))
    await workspace.previewNow()
    try workspace.apply()
    #expect(
      sidebar.pipeline.steps.map(\.recipe.processID) == [
        "channel-combination", "stretch", "curves",
      ])
    #expect(
      ParamSet.loading(sidebar.pipeline.steps[1].recipe.params, onto: StretchProcess.schema)
        .params.number("targetBackground") == 0.3)

    await sidebar.run()
    #expect(sidebar.events == [.stopped(2)] && sidebar.canContinue)
    sidebar.save(as: "kept")
    #expect(sidebar.stoppedAt == 2 && sidebar.canContinue, "saving keeps where the run stands")
    sidebar.setMode(.auto, of: 2)
    #expect(!sidebar.canContinue, "no breakpoint any more")
    sidebar.setMode(.stop, of: 2)

    // Masked Apply: recorded, with a warning that a replay is unmasked.
    try workspace.undo()
    workspace.choose(StretchProcess.id)
    workspace.mask = Mask(source: .luminosityRange(low: 0, high: 1, softness: 0))
    await workspace.previewNow()
    try workspace.apply()
    #expect(sidebar.warnings.contains { $0.contains("under a mask") })
  }

  @Test("a Run on this stack never reuses its own history as the previous run", .scratchDirectory)
  func testRunWithoutPreviousReusesNothing() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let pipeline = Pipeline(
      name: "p",
      steps: [
        try Self.step(ChannelCombinationProcess.self),
        try Self.step(StretchProcess.self, locked: true),
      ])
    let (workspace, sidebar) = try Self.sidebar(opened, pipeline)
    await sidebar.run()
    try workspace.undo()
    await sidebar.run()
    #expect(sidebar.events == [.applied(1)], "the same history is never its own previous run")
  }
}
