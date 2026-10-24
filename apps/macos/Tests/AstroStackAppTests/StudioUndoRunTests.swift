import AstroStackApp
import Foundation
import Metal
import ProcessKit
import ProjectKit
import TestSupport
import Testing

/// Card 0117: a pipeline run is one ⌘Z that puts the column back with the history; a move is
/// refused, not consumed, while the history is being moved; the history's buttons and ⌘Z share
/// one stack, recognised by an owner tag, never by the action's name.
@MainActor
@Suite(
  "Studio undo — one move per run, breakpoint restored, refusal kept, one stack",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
struct StudioUndoRunTests {
  /// The window's undo manager, driven by explicit groups as a test needs it (each Studio move
  /// opens its own).
  static func undoManager() -> ProjectUndoManager {
    let undoManager = ProjectUndoManager()
    undoManager.groupsByEvent = false
    return undoManager
  }

  /// Runs `body` as one undo group of `undoManager`.
  static func grouped(_ undoManager: UndoManager, _ body: () async -> Void) async {
    undoManager.beginUndoGrouping()
    await body()
    undoManager.endUndoGrouping()
  }

  /// Applies `processID` with its defaults through the panel, registered on `undoManager`.
  static func apply(
    _ processID: String, _ workspace: StudioWorkspaceModel, _ undoManager: UndoManager
  ) async {
    workspace.choose(processID)
    await workspace.previewNow()
    StudioUndo.apply(workspace, undoManager: undoManager)
  }

  static func ids(_ workspace: StudioWorkspaceModel) -> [String] {
    workspace.studio.steps.map(\.processID)
  }

  static let all = ["channel-combination", "stretch", "curves", "saturation"]

  @Test(
    "a run is undone in one ⌘Z and redone in one ⇧⌘Z, named « Run Pipeline »", .scratchDirectory)
  func testRun_UndoneInOneMove_RedoneInOne() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let (workspace, sidebar) = try PipelineSidebarModelTests.sidebar(
      opened, try PipelineSidebarModelTests.fourSteps())
    let undoManager = Self.undoManager()
    await sidebar.run(undoManager: undoManager)
    #expect(Self.ids(workspace) == Self.all)
    #expect(undoManager.undoActionName == String(localized: .app("Run Pipeline")))

    undoManager.undo()
    #expect(Self.ids(workspace) == ["channel-combination"])
    #expect(!undoManager.canUndo, "one move took the whole run back")
    #expect(undoManager.redoActionName == String(localized: .app("Run Pipeline")))
    undoManager.redo()
    #expect(Self.ids(workspace) == Self.all)
    #expect(!undoManager.canRedo)
  }

  @Test(
    "undoing a Continue puts the breakpoint and its values back; redo applies the edited ones",
    .scratchDirectory)
  func testRun_Undo_RestoresBreakpointAndRecipe() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let (workspace, sidebar) = try PipelineSidebarModelTests.sidebar(
      opened, try PipelineSidebarModelTests.fourSteps(stop: true))
    let undoManager = Self.undoManager()
    await sidebar.run(undoManager: undoManager)
    let planned = sidebar.pipeline.steps[2].recipe
    let edited = CurvePoint(0.5, 0.6)
    try #require(workspace.panel).set("rgb", .points([CurvePoint(0, 0), edited, CurvePoint(1, 1)]))
    await sidebar.continueRun(undoManager: undoManager)
    #expect(Self.ids(workspace) == Self.all && sidebar.stoppedAt == nil)
    let continued = sidebar.pipeline.steps[2].recipe
    #expect(continued != planned)

    undoManager.undo()
    #expect(Self.ids(workspace) == ["channel-combination", "stretch"])
    #expect(sidebar.stoppedAt == 2 && sidebar.pipeline.steps[2].recipe == planned)
    #expect(sidebar.canContinue, "Continue is offered again at the breakpoint")
    undoManager.redo()
    #expect(Self.ids(workspace) == Self.all && sidebar.stoppedAt == nil)
    #expect(sidebar.pipeline.steps[2].recipe == continued)
    undoManager.undo()
    undoManager.undo()
    #expect(Self.ids(workspace) == ["channel-combination"] && sidebar.stoppedAt == nil)
  }

  @Test("while a host tool moves the history, ⌘Z is greyed and its move kept", .scratchDirectory)
  func testUndo_RefusedWhileRunning_IsNotConsumed() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let during = BackgroundProcessTests.During()
    let (workspace, _) = try PipelineSidebarModelTests.toolSidebar(
      opened, try PipelineSidebarModelTests.fourSteps(),
      tool: BackgroundProcessTests.tool(during: during))
    let undoManager = Self.undoManager()
    await Self.apply(StretchProcess.id, workspace, undoManager)
    let seen = Recorded<Bool>()
    during.set {
      seen.append(workspace.isMovingHistory && !undoManager.canUndo)
      undoManager.undo()
      StudioUndo.undo(workspace, undoManager: undoManager)
      seen.append(Self.ids(workspace) == ["channel-combination", "stretch"])
    }
    workspace.choose(BackgroundExtractionProcess.id)
    let recorded = Recorded<Bool>()
    workspace.startTool { recorded.append($0) }
    while recorded.all.isEmpty { await Task.yield() }
    #expect(recorded.all == [true] && seen.all == [true, true], "refused, nothing moved meanwhile")
    #expect(undoManager.canUndo && undoManager.undoCount == 1, "the stretch's move was kept")
  }

  @Test("the history's buttons and ⌘Z go on from each other, both ways", .scratchDirectory)
  func testHistoryButtons_AndCommandZ_ShareOneStack() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let (workspace, sidebar) = try PipelineSidebarModelTests.sidebar(
      opened, try PipelineSidebarModelTests.fourSteps())
    let undoManager = Self.undoManager()
    await Self.apply(StretchProcess.id, workspace, undoManager)
    await sidebar.run(undoManager: undoManager)
    #expect(Self.ids(workspace) == Self.all)

    StudioUndo.undo(workspace, undoManager: undoManager)
    #expect(Self.ids(workspace) == ["channel-combination", "stretch"], "the button took the run")
    undoManager.undo()
    #expect(Self.ids(workspace) == ["channel-combination"], "⌘Z goes on")
    StudioUndo.redo(workspace, undoManager: undoManager)
    undoManager.redo()
    #expect(Self.ids(workspace) == Self.all)
    #expect(!undoManager.canRedo)
  }

  @Test(
    "a button move behind another action registers its inverse; no stale entry is left",
    .scratchDirectory)
  func testHistoryButtons_BehindAnotherAction_NoStaleEntry() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try StudioWorkspaceModelTests.workspace(
      opened, bundle: StudioModelTests.bundle())
    let undoManager = Self.undoManager()
    let other = Recorded<Int>()
    await Self.apply(StretchProcess.id, workspace, undoManager)
    // Another stage's action on top, even one named like a Studio step: not the buttons' own.
    await Self.grouped(undoManager) {
      undoManager.registerUndo(withTarget: other) { $0.append(1) }
      undoManager.setActionName(String(localized: .app("Studio Step")))
    }

    StudioUndo.undo(workspace, undoManager: undoManager)
    #expect(Self.ids(workspace) == ["channel-combination"] && other.all.isEmpty)
    undoManager.undo()
    #expect(Self.ids(workspace) == ["channel-combination", "stretch"], "⌘Z undid the button")
    StudioUndo.undo(workspace, undoManager: undoManager)
    await Self.apply(CurvesProcess.id, workspace, undoManager)
    #expect(Self.ids(workspace) == ["channel-combination", "curves"])

    var moves: [[String]] = []
    // Bounded: a no-op entry left on the stack would otherwise loop for ever.
    for _ in 0..<5 where undoManager.canUndo {
      undoManager.undo()
      moves.append(Self.ids(workspace))
    }
    // The curves step back, then the other action: the button's moves left no stale entry.
    #expect(moves == [["channel-combination"], ["channel-combination"]])
    #expect(other.all == [1])
  }

  @Test("a replay on another stack is undone in one ⌘Z", .scratchDirectory)
  func testReplay_IsUndoable() async throws {
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

    window.replayPipeline(on: stacks[1].id)
    await ProjectWindowWorkspaceTests.settle {
      window.selectedStackID == stacks[1].id && window.workspace?.studio.steps.count == 2
    }
    let replayed = try #require(window.workspace)
    let column = try #require(replayed.pipeline)
    #expect(Self.ids(replayed) == ["channel-combination", "stretch"])
    #expect(column.pipeline.steps.count == 2, "the replayed pipeline")
    undoManager.undo()
    #expect(Self.ids(replayed) == ["channel-combination"])
    #expect(column.pipeline.steps.count == 1, "the stack's own pipeline is back")
  }
}

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
}
