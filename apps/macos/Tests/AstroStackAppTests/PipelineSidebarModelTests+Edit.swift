import AstroStackApp
import Foundation
import Metal
import ProcessKit
import ProjectKit
import RenderKit
import TestSupport
import Testing

/// Card 0107: a step not applied yet is removed or moved; a done one is refused with its reason;
/// the breakpoint follows its step; both are undoable.
extension PipelineSidebarModelTests {
  /// Channel combination, stretch, curves (a breakpoint when `stop`), saturation.
  static func fourSteps(stop: Bool = false) throws -> Pipeline {
    Pipeline(
      name: "p",
      steps: [
        try step(ChannelCombinationProcess.self), try step(StretchProcess.self),
        try step(CurvesProcess.self, [:], stop ? .stop : .auto), try step(SaturationProcess.self),
      ])
  }

  static func ids(_ sidebar: PipelineSidebarModel) -> [String] {
    sidebar.pipeline.steps.map(\.recipe.processID)
  }

  @Test("a step not applied yet is removed", .scratchDirectory)
  func testRemove_NotDoneStep() throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let (_, sidebar) = try Self.sidebar(opened, try Self.fourSteps())
    #expect(sidebar.canEdit(2) && sidebar.editRefusal(of: 2) == nil)
    sidebar.remove(at: 2)
    #expect(Self.ids(sidebar) == ["channel-combination", "stretch", "saturation"])
  }

  @Test("a done step is neither removed nor moved: the reason is shown", .scratchDirectory)
  func testRemove_DoneStep_Refused() throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let (_, sidebar) = try Self.sidebar(opened, try Self.fourSteps())
    let before = sidebar.pipeline
    #expect(!sidebar.canEdit(0))
    #expect(sidebar.editRefusal(of: 0) == .app("Undo back before this step to change it"))
    sidebar.remove(at: 0)
    sidebar.move(from: 0, to: 2)
    #expect(sidebar.pipeline == before)
    #expect(!sidebar.canEdit(4) && !sidebar.canEdit(-1), "no such step")
  }

  @Test("a step is never moved into the done steps", .scratchDirectory)
  func testMove_IntoDoneRange_Refused() throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let (_, sidebar) = try Self.sidebar(opened, try Self.fourSteps())
    let before = sidebar.pipeline
    sidebar.move(from: 3, to: 0)
    #expect(sidebar.pipeline == before)
    sidebar.move(from: 3, to: 1)
    #expect(Self.ids(sidebar) == ["channel-combination", "saturation", "stretch", "curves"])
  }

  @Test("removing the step the run halted at clears the breakpoint", .scratchDirectory)
  func testRemove_StoppedStep_ClearsBreakpoint() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let (workspace, sidebar) = try Self.sidebar(opened, try Self.fourSteps(stop: true))
    await sidebar.run()
    #expect(sidebar.stoppedAt == 2 && sidebar.canContinue)
    sidebar.remove(at: 3)
    #expect(sidebar.stoppedAt == 2 && sidebar.canContinue, "a later step leaves it")
    sidebar.remove(at: 2)
    #expect(sidebar.stoppedAt == nil && !sidebar.canContinue)
    #expect(workspace.panel?.type.id == CurvesProcess.id, "the panel keeps its process")
    #expect(sidebar.status(of: 1) == .done && Self.ids(sidebar).count == 2)
  }

  @Test("removing a step before the breakpoint shifts it with its step", .scratchDirectory)
  func testRemove_BeforeStopped_ShiftsIndex() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let (workspace, sidebar) = try Self.sidebar(opened, try Self.fourSteps(stop: true))
    await sidebar.run()
    try workspace.undo()  // the stretch is no longer applied: it can go
    workspace.choose(CurvesProcess.id)
    #expect(sidebar.stoppedAt == 2 && !sidebar.canContinue)
    sidebar.remove(at: 1)
    #expect(sidebar.stoppedAt == 1 && sidebar.status(of: 1) == .current)
    #expect(sidebar.canContinue, "the history stands right before the curves again")
  }

  @Test(
    "moving a step across the breakpoint shifts it; Run applies the moved step first",
    .scratchDirectory)
  func testMove_AcrossStopped_ShiftsIndex() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let (workspace, sidebar) = try Self.sidebar(opened, try Self.fourSteps(stop: true))
    await sidebar.run()
    sidebar.move(from: 3, to: 2)
    #expect(Self.ids(sidebar) == ["channel-combination", "stretch", "saturation", "curves"])
    #expect(sidebar.stoppedAt == 3 && !sidebar.canContinue)
    await sidebar.run()
    #expect(sidebar.failure == nil && sidebar.stoppedAt == 3 && sidebar.canContinue)
    #expect(workspace.studio.steps.map(\.processID).last == SaturationProcess.id)
    sidebar.move(from: 3, to: 3)
    #expect(sidebar.stoppedAt == 3 && sidebar.canContinue, "in place changes nothing")
  }

  @Test("Run after a removal applies the other steps; the history follows", .scratchDirectory)
  func testRun_AfterRemove_SkipsStep() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let (workspace, sidebar) = try Self.sidebar(opened, try Self.fourSteps())
    sidebar.remove(at: 2)
    await sidebar.run()
    #expect(sidebar.failure == nil)
    #expect(workspace.studio.steps.map(\.processID) == Self.ids(sidebar))
    #expect(!sidebar.canEdit(2), "applied now")
  }

  @Test(
    "an edited pipeline saves and loads back; the compare sheet lists the removed step",
    .scratchDirectory)
  func testSaveLoad_AfterRemoveMove_RoundTrips() throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let (_, sidebar) = try Self.sidebar(opened, try Self.fourSteps())
    sidebar.save(as: "full")
    sidebar.move(from: 3, to: 1)
    sidebar.remove(at: 3)
    #expect(
      try sidebar.differences(from: "full").last
        == PipelineDiff.Entry(step: 3, processID: SaturationProcess.id, change: .removed))
    sidebar.save(as: "edited")
    let edited = sidebar.pipeline
    sidebar.load("full")
    #expect(Self.ids(sidebar).count == 4)
    sidebar.load("edited")
    #expect(sidebar.pipeline == edited && sidebar.failure == nil)
  }

  @Test("undo puts a removed step back; redo removes it again", .scratchDirectory)
  func testUndoRemove_RestoresStep() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let (_, sidebar) = try Self.sidebar(opened, try Self.fourSteps(stop: true))
    await sidebar.run()
    let before = sidebar.pipeline
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    undoManager.beginUndoGrouping()
    sidebar.remove(at: 2, undoManager: undoManager)
    undoManager.endUndoGrouping()
    #expect(sidebar.stoppedAt == nil)
    undoManager.undo()
    #expect(sidebar.pipeline == before && sidebar.stoppedAt == 2 && sidebar.canContinue)
    undoManager.redo()
    #expect(sidebar.pipeline == before.removing(at: 2) && sidebar.stoppedAt == nil)
  }

  @Test("undo of a removal still works after a breakpoint toggled elsewhere", .scratchDirectory)
  func testUndoRemove_AfterToggle_KeepsToggle() throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let (workspace, sidebar) = try Self.sidebar(opened, try Self.fourSteps())
    var revealed = 0
    workspace.reveal = { revealed += 1 }
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    undoManager.beginUndoGrouping()
    sidebar.remove(at: 2, undoManager: undoManager)
    undoManager.endUndoGrouping()
    sidebar.setMode(.stop, of: 2)
    undoManager.undo()
    #expect(Self.ids(sidebar) == ["channel-combination", "stretch", "curves", "saturation"])
    #expect(sidebar.pipeline.steps[3].mode == .stop, "the toggle made since is kept")
    #expect(revealed == 1, "an undo brings the Studio into view")
  }

  @Test("undo restores the order; it does nothing once the history moved on", .scratchDirectory)
  func testUndoMove_RestoresOrder() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let (_, sidebar) = try Self.sidebar(opened, try Self.fourSteps())
    let before = sidebar.pipeline
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    undoManager.beginUndoGrouping()
    sidebar.move(from: 3, to: 1, undoManager: undoManager)
    undoManager.endUndoGrouping()
    undoManager.undo()
    #expect(sidebar.pipeline == before)

    undoManager.redo()
    let moved = sidebar.pipeline
    await sidebar.run()
    undoManager.undo()
    #expect(sidebar.pipeline == moved, "the moved steps are applied: undo the history first")
  }
}
