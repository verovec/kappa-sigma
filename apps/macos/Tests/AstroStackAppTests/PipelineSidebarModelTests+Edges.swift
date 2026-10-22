import AstroStackApp
import Foundation
import Metal
import ProcessKit
import ProjectKit
import RenderKit
import TestSupport
import Testing

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

extension PipelineSidebarModelTests {
  @Test(
    "refusals and failures are said: a diverged history, an unknown process, a missing file",
    .scratchDirectory)
  func testFailuresAreSaid() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let pipeline = Pipeline(
      name: "p",
      steps: [
        try Self.step(ChannelCombinationProcess.self),
        PipelineStep(recipe: Recipe(processID: "nope", params: ParamSet(schema: ParamSchema([])))),
      ])
    let (workspace, sidebar) = try Self.sidebar(opened, pipeline)
    await sidebar.run()
    #expect(sidebar.failure != nil && workspace.studio.steps.count == 1, "unknown process")

    sidebar.show(Pipeline(name: "other", steps: [try Self.step(StretchProcess.self)]))
    await sidebar.run()
    #expect(sidebar.failure != nil, "the history does not follow it")

    sidebar.load("missing")
    #expect(sidebar.failure != nil)
    sidebar.show(pipeline, warnings: ["unknown key colour ignored"])
    let ids = AccessibilityAuditTests.entries(PipelineSidebarView(model: sidebar)).map(\.id)
    #expect(ids.contains("fr.astrostack.stage.studio.pipeline.run"))
  }

  @Test("the compare sheet words every kind of difference", .scratchDirectory)
  func testCompareSheetVariants() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let base = Pipeline(
      name: "base",
      steps: [
        try Self.step(ChannelCombinationProcess.self),
        try Self.step(StretchProcess.self, ["linked": .flag(true)]),
        try Self.step(CurvesProcess.self),
      ])
    let (_, sidebar) = try Self.sidebar(opened, base)
    sidebar.save(as: "base")
    let variants: [Pipeline] = [
      base,
      Pipeline(
        name: "v",
        steps: [
          try Self.step(ChannelCombinationProcess.self),
          try Self.step(StretchProcess.self, ["linked": .flag(false)], .stop),
          try Self.step(SaturationProcess.self), try Self.step(CurvesProcess.self),
        ]),
      Pipeline(name: "short", steps: [try Self.step(ChannelCombinationProcess.self)]),
    ]
    for variant in variants {
      sidebar.show(variant)
      for language in ["fr", "en"] {
        let ids = AccessibilityAuditTests.entries(
          PipelineDiffSheet(model: sidebar, savedName: "base") {}, language: language
        ).map(\.id)
        #expect(ids == ["fr.astrostack.stage.studio.pipeline.compare.close"])
      }
    }
    sidebar.show(variants[1])
    let changes = try sidebar.differences(from: "base").map(\.change)
    #expect(changes.contains(.process("curves", "saturation")) && changes.contains(.added))
  }

  @Test("a reopened history shows its profile while it follows it, else its own steps")
  func testProfileOrOwnSteps() throws {
    let profile = Pipeline(
      name: "emission-osc-dualband",
      steps: [try Self.step(ChannelCombinationProcess.self), try Self.step(StretchProcess.self)])
    func step(_ id: String) -> Recipe {
      Recipe(processID: id, params: ParamSet(schema: ParamSchema([])))
    }
    let following = ProjectWindowModel.pipeline(
      applied: [step("channel-combination")], profile: profile)
    #expect(following.0 == profile && following.1.isEmpty)
    let diverged = ProjectWindowModel.pipeline(
      applied: [step("channel-combination"), step("curves")], profile: profile)
    #expect(diverged.0.steps.map(\.recipe.processID) == ["channel-combination", "curves"])
    #expect(diverged.1.count == 1)
    #expect(ProjectWindowModel.pipeline(applied: [], profile: nil).0.steps.isEmpty)
  }
}
