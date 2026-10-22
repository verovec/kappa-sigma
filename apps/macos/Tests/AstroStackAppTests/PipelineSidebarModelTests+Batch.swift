import AstroStackApp
import Foundation
import ProcessKit
import TestSupport
import Testing

extension PipelineSidebarModelTests {
  static func toolSidebar(
    _ opened: StudioModelTests.Opened, _ pipeline: Pipeline,
    tool: StudioTool = BackgroundProcessTests.tool()
  ) throws -> (StudioWorkspaceModel, PipelineSidebarModel) {
    let workspace = try BackgroundProcessTests.workspace(opened, tool: tool)
    let sidebar = try PipelineSidebarModel(
      workspace: workspace, pipeline: pipeline, store: opened.package.store,
      base: [.color, .emission])
    workspace.pipeline = sidebar
    return (workspace, sidebar)
  }

  /// Card 0092 on card 0093's rule: a pipeline's background-extraction step is greyed with its
  /// reason (a host tool is applied in the Studio); a manual Apply of it becomes a pipeline step
  /// with its values (R5).
  @Test("a tool step is greyed in the pipeline; a manual tool Apply is recorded", .scratchDirectory)
  func testToolStepGreyedAndRecorded() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let (workspace, sidebar) = try Self.toolSidebar(
      opened,
      Pipeline(
        name: "p",
        steps: [
          try Self.step(ChannelCombinationProcess.self),
          try Self.step(BackgroundExtractionProcess.self),
        ]))
    #expect(sidebar.stepProblems[1] == ["runs a host tool: apply it in the Studio"])

    workspace.choose(BackgroundExtractionProcess.id)
    try #require(workspace.panel).set("applyTo", .choice("all"))
    #expect(await workspace.runTool())
    #expect(sidebar.pipeline.steps.count == 2, "the planned step is the one done")
    let recipe = try #require(sidebar.pipeline.steps.last?.recipe)
    #expect(recipe.processID == BackgroundExtractionProcess.id)
    #expect(recipe.params.contains { $0.id == "applyTo" && $0.value == .choice("all") })
  }

  /// A Run of the column waits for a tool Apply (its step is recorded on the head it started
  /// from), and a tool Apply waits for a Run.
  @Test("a Run and a tool Apply exclude each other", .scratchDirectory)
  func testRunAndToolExclusion() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let during = BackgroundProcessTests.During()
    let (workspace, sidebar) = try Self.toolSidebar(
      opened,
      Pipeline(
        name: "p",
        steps: [
          try Self.step(ChannelCombinationProcess.self),
          try Self.step(StretchProcess.self),
        ]),
      tool: BackgroundProcessTests.tool(during: during))
    workspace.choose(BackgroundExtractionProcess.id)
    let recorded = Recorded<Bool>()
    workspace.startTool { recorded.append($0) }
    await sidebar.run()
    #expect(sidebar.failure != nil, "Run refused while the tool Apply is going")
    while recorded.all.isEmpty { await Task.yield() }
    #expect(recorded.all == [true])
    #expect(
      workspace.studio.steps.map(\.processID) == [
        ChannelCombinationProcess.id, BackgroundExtractionProcess.id,
      ])
  }
}

extension PipelineSidebarModelTests {
  @Test("no step is removed while a tool Apply is going (card 0107)", .scratchDirectory)
  func testRemove_DuringToolApply_Refused() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let (workspace, sidebar) = try Self.toolSidebar(
      opened,
      Pipeline(
        name: "p",
        steps: [
          try Self.step(ChannelCombinationProcess.self), try Self.step(StretchProcess.self),
        ]),
      tool: BackgroundProcessTests.tool(during: BackgroundProcessTests.During()))
    workspace.choose(BackgroundExtractionProcess.id)
    let recorded = Recorded<Bool>()
    workspace.startTool { recorded.append($0) }
    #expect(
      sidebar.editRefusal(of: 1) == .app("A tool is already running: wait for it, or stop it."))
    sidebar.remove(at: 1)
    #expect(sidebar.pipeline.steps.count == 2)
    while recorded.all.isEmpty { await Task.yield() }
  }
}
