import AstroStackApp
import Foundation
import Metal
import ProcessKit
import ProjectKit
import TestSupport
import Testing

/// Card 0117: the window's undo manager, replays, the column put back, refusals of its edits.
extension StudioUndoRunTests {
  @Test(
    "the project window undoes through a ProjectUndoManager, the one a replay registers on",
    .scratchDirectory)
  func testProjectWindow_UndoManager_IsTheDocuments() throws {
    let url = try ScratchDirectory.url.appendingPathComponent("M31.astrostack")
    try ProjectPackage.create(at: url).close()
    let document = try ProjectDocument(contentsOf: url, ofType: ProjectDocumentTests.type)
    defer { document.close() }
    document.makeWindowControllers()

    let window = try #require(document.windowControllers.first?.window)
    let undoManager = try #require(document.undoManager as? ProjectUndoManager)
    #expect(window.undoManager === undoManager)
    #expect(document.windowModel?.undoManager() === undoManager)
  }

  @Test(
    "a button move behind another action keeps the earlier ⌘Z entries chained",
    .scratchDirectory)
  func testHistoryButtons_BehindAnotherAction_KeepEarlierMoves() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try StudioWorkspaceModelTests.workspace(
      opened, bundle: StudioModelTests.bundle())
    let undoManager = Self.undoManager()
    let other = Recorded<Int>()
    await Self.apply(StretchProcess.id, workspace, undoManager)
    await Self.apply(CurvesProcess.id, workspace, undoManager)
    await Self.grouped(undoManager) { undoManager.registerUndo(withTarget: other) { $0.append(1) } }

    StudioUndo.undo(workspace, undoManager: undoManager)
    var moves: [[String]] = []
    for _ in 0..<5 where undoManager.canUndo {
      undoManager.undo()
      moves.append(Self.ids(workspace))
    }
    let stretched = ["channel-combination", "stretch"]
    #expect(
      moves == [
        Self.all.prefix(3).map(\.self), Self.all.prefix(3).map(\.self), stretched,
        ["channel-combination"],
      ])
    #expect(other.all == [1])
  }

  @Test("a breakpoint comes back only on the step it named", .scratchDirectory)
  func testRestore_BreakpointOnAnotherStep_IsCleared() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let (workspace, sidebar) = try PipelineSidebarModelTests.sidebar(
      opened, try PipelineSidebarModelTests.fourSteps(stop: true))
    await sidebar.run()
    let halted = sidebar.mark()
    #expect(sidebar.stoppedAt == 2)

    var moved = try PipelineSidebarModelTests.fourSteps(stop: true)
    moved.steps.swapAt(2, 3)
    sidebar.show(moved)
    sidebar.restore(halted)
    #expect(sidebar.stoppedAt == nil, "step 2 is no longer the curves it halted before")
    sidebar.show(try PipelineSidebarModelTests.fourSteps(stop: true))
    workspace.closePanel()
    sidebar.restore(halted)
    #expect(sidebar.stoppedAt == 2 && workspace.panel?.type.id == CurvesProcess.id)
  }

  @Test(
    "a pipeline-column edit on top is kept, not consumed, while a host tool runs",
    .scratchDirectory)
  func testUndo_ColumnEditRefusedWhileRunning_IsNotConsumed() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let during = BackgroundProcessTests.During()
    let (workspace, sidebar) = try PipelineSidebarModelTests.toolSidebar(
      opened, try PipelineSidebarModelTests.fourSteps(),
      tool: BackgroundProcessTests.tool(during: during))
    let undoManager = Self.undoManager()
    await Self.grouped(undoManager) { sidebar.remove(at: 3, undoManager: undoManager) }
    let seen = Recorded<Bool>()
    during.set {
      seen.append(!undoManager.canUndo)
      undoManager.undo()
      seen.append(sidebar.pipeline.steps.count == 3)
    }
    workspace.choose(BackgroundExtractionProcess.id)
    let recorded = Recorded<Bool>()
    workspace.startTool { recorded.append($0) }
    while recorded.all.isEmpty { await Task.yield() }
    #expect(seen.all == [true, true], "refused while the tool ran")
    undoManager.undo()
    // The tool's Apply became a step of the pipeline (R5); the removed saturation is back.
    let ids = sidebar.pipeline.steps.map(\.recipe.processID)
    #expect(ids.count == 5 && ids.contains(SaturationProcess.id))
  }

  @Test("undoing a replay puts back the warnings of the pipeline it replaced", .scratchDirectory)
  func testRestore_WholePipeline_KeepsItsWarnings() throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try StudioWorkspaceModelTests.workspace(
      opened, bundle: StudioModelTests.bundle())
    let sidebar = try PipelineSidebarModel(
      workspace: workspace, pipeline: try PipelineSidebarModelTests.fourSteps(),
      warnings: ["loaded with a warning"], store: opened.package.store, base: [.color])
    let before = sidebar.mark(whole: true)
    sidebar.show(Pipeline(name: "replayed", steps: []))
    #expect(sidebar.warnings.isEmpty)
    sidebar.restore(before)
    #expect(sidebar.pipeline.name == "p" && sidebar.warnings == ["loaded with a warning"])
  }

  @Test("a replay that halts before its first step is still undone in one ⌘Z", .scratchDirectory)
  func testReplay_NothingAdded_StillUndoable() async throws {
    let fixture = try ProjectTests.fixture()
    defer { try? fixture.project.close() }
    let stacks = try ProjectWindowWorkspaceTests.twoStacks(fixture)
    let window = fixture.window
    let undoManager = Self.undoManager()
    window.undoManager = { undoManager }
    window.refresh()
    window.selectStack(stacks[0].id)
    window.select(.studio)
    await window.openStudio()
    await ProjectWindowWorkspaceTests.settle { window.workspace?.pipeline != nil }
    window.workspace?.choose(StretchProcess.id)
    await window.workspace?.previewNow()
    try window.workspace?.apply()
    window.workspace?.pipeline?.setMode(.stop, of: 1)

    window.replayPipeline(on: stacks[1].id)
    await ProjectWindowWorkspaceTests.settle {
      window.selectedStackID == stacks[1].id && window.workspace?.pipeline?.stoppedAt == 1
    }
    let column = try #require(window.workspace?.pipeline)
    #expect(column.pipeline.steps.count == 2 && undoManager.canUndo)
    undoManager.undo()
    #expect(column.pipeline.steps.count == 1 && column.stoppedAt == nil)
  }
}
