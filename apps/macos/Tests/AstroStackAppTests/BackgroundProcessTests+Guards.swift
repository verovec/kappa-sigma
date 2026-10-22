import AstroStackApp
import Foundation
import ImageKit
import ProcessKit
import StackKit
import TestSupport
import Testing

extension BackgroundProcessTests {
  @Test(
    "a head moved while the tool ran: the result is refused, the history kept", .scratchDirectory)
  func testHeadMovedDuringRun() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let during = During()
    let workspace = try Self.workspace(opened, tool: Self.tool(during: during))
    try workspace.studio.apply(StretchProcess.id, params: ParamSet(schema: StretchProcess.schema))
    during.set { try? workspace.studio.undo() }
    workspace.choose(BackgroundExtractionProcess.id)
    #expect(await workspace.runTool() == false)
    #expect(workspace.studio.steps.map(\.processID) == ["channel-combination"])
    #expect(workspace.failure != nil)
  }

  @Test(
    "Siril cannot divide: greyed with the reason and refused before any tool", .scratchDirectory)
  func testSirilDivideRefused() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let calls = Calls()
    let workspace = try Self.workspace(opened, tool: Self.tool(calls: calls))
    workspace.choose(BackgroundExtractionProcess.id)
    let panel = try #require(workspace.panel)
    panel.set("engine", .choice("siril-rbf"))
    panel.set("correction", .choice("divide"))
    #expect(panel.unavailableOptions["correction"]?["divide"] != nil)
    #expect(await workspace.runTool() == false)
    #expect(calls.engines.isEmpty && workspace.failure != nil)
    panel.set("engine", .choice("graxpert"))
    #expect(panel.unavailableOptions["correction"]?["divide"] == nil)
  }

  @Test("choosing or closing leaves no model view", .scratchDirectory)
  func testNoStaleModelView() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.workspace(opened)
    workspace.choose(BackgroundExtractionProcess.id)
    #expect(await workspace.runTool())
    try workspace.toggleModel()
    workspace.closePanel()
    #expect(!workspace.showsModel)
    #expect(workspace.viewer.model.image.planes == workspace.studio.head.planes)
    workspace.choose(BackgroundExtractionProcess.id)
    try workspace.toggleModel()
    workspace.choose(StretchProcess.id)
    #expect(!workspace.showsModel)
  }

  /// Apply of the tool through the window's undo manager: the move is registered once the
  /// step is recorded, and ⌘Z takes it back.
  @Test("a tool Apply registers its undo when the step is recorded", .scratchDirectory)
  func testToolApplyRegistersUndo() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.workspace(opened)
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    workspace.choose(BackgroundExtractionProcess.id)
    undoManager.beginUndoGrouping()
    await withCheckedContinuation { done in
      StudioUndo.apply(workspace, undoManager: undoManager) { done.resume() }
    }
    undoManager.endUndoGrouping()
    #expect(workspace.studio.steps.count == 2)
    #expect(undoManager.canUndo)
    undoManager.undo()
    #expect(workspace.studio.steps.count == 1)
  }
}
