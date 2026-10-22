import AstroStackApp
import Foundation
import ProcessKit
import TestSupport
import Testing

extension PipelineSidebarModelTests {
  static func batchSidebar(
    _ opened: StudioModelTests.Opened, _ pipeline: Pipeline,
    calls: BackgroundProcessTests.Calls = .init(),
    during: BackgroundProcessTests.During = .init()
  ) throws -> (StudioWorkspaceModel, PipelineSidebarModel) {
    let workspace = try BackgroundProcessTests.workspace(
      opened, tools: BackgroundProcessTests.tools(during: during, calls: calls))
    let sidebar = try PipelineSidebarModel(
      workspace: workspace, pipeline: pipeline, store: opened.package.store,
      base: [.color, .emission])
    workspace.pipeline = sidebar
    return (workspace, sidebar)
  }

  /// Card 0092: a pipeline's background-extraction step runs through the workspace's tools —
  /// at Run and at Continue — never stops with `noTool`.
  @Test(
    "Run and Continue run a background-extraction step with the workspace's tools",
    .scratchDirectory)
  func testRunsBatchStep() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let calls = BackgroundProcessTests.Calls()
    let pipeline = Pipeline(
      name: "p",
      steps: [
        try Self.step(ChannelCombinationProcess.self),
        try Self.step(BackgroundExtractionProcess.self, ["engine": .choice("siril-rbf")]),
        try Self.step(BackgroundExtractionProcess.self, [:], .stop),
      ])
    let (workspace, sidebar) = try Self.batchSidebar(opened, pipeline, calls: calls)
    await sidebar.run()
    #expect(sidebar.failure == nil)
    #expect(calls.engines == ["siril-rbf"] && sidebar.stoppedAt == 2)
    #expect(sidebar.canContinue)
    await sidebar.continueRun()
    #expect(sidebar.failure == nil)
    #expect(calls.engines == ["siril-rbf", "graxpert"])
    #expect(workspace.studio.steps.count == 3)
  }

  /// Card 0092: a manual Apply of background extraction becomes a pipeline step (R5); a run of
  /// the column waits for a tool Apply.
  @Test("a manual tool Apply is recorded as a step; Run waits for a tool Apply", .scratchDirectory)
  func testManualBatchApplyAndExclusion() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let (workspace, sidebar) = try Self.batchSidebar(
      opened, Pipeline(name: "p", steps: [try Self.step(ChannelCombinationProcess.self)]))
    workspace.choose(BackgroundExtractionProcess.id)
    try #require(workspace.panel).set("applyTo", .choice("all"))
    workspace.startBatch()
    await sidebar.run()
    #expect(sidebar.failure != nil, "Run refused while the tool Apply is going")
    await workspace.batchTask?.value
    #expect(
      sidebar.pipeline.steps.map(\.recipe.processID) == [
        ChannelCombinationProcess.id, BackgroundExtractionProcess.id,
      ])
    #expect(
      sidebar.pipeline.steps.last?.recipe.params.contains {
        $0.id == "applyTo" && $0.value == .choice("all")
      } == true)
    #expect(workspace.studio.steps.count == 2)
  }
}
