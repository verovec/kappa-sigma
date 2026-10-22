import AppKit
import AstroStackApp
import Foundation
import ImageKit
import Metal
import ProcessKit
import StackKit
import TestSupport
import Testing

extension StudioToolsTests {
  /// The installed-tools client over a machine without GraXpert: a GraXpert request fails with
  /// GraXpert's own error, nothing else runs (R2); its scratch is the folder given.
  @Test("the live tools name a missing GraXpert, never another engine", .scratchDirectory)
  func testLiveMissingGraXpert() async throws {
    let scratch = try ScratchDirectory.url.appendingPathComponent("bge")
    let tools = StudioTools.live(
      scratch: scratch,
      hostTools: HostTools { .missing(path: "/nowhere/\($0.productName)") })
    #expect(tools.scratch == scratch)
    #expect(await tools.locate(.graxpert) == .missing(path: "/nowhere/GraXpert"))
    let image = AstroImage(
      width: 2, height: 2, planes: [[0.1, 0.2, 0.3, 0.4]],
      metadata: ImageMetadata(rowOrder: .topDown))
    await #expect(throws: GraXpertError.missing(path: "/nowhere/GraXpert")) {
      _ = try await tools.background(
        image, ParamSet(schema: BackgroundExtractionProcess.schema)
      ) { _ in }
    }
  }
}

extension BackgroundProcessTests {
  /// Apply of a batch process through the window's undo manager: the move is registered once
  /// the tool's step is recorded, and ⌘Z takes it back.
  @Test("a batch Apply registers its undo when the step is recorded", .scratchDirectory)
  func testBatchApplyRegistersUndo() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.workspace(opened, tools: Self.tools())
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    workspace.choose(BackgroundExtractionProcess.id)
    undoManager.beginUndoGrouping()
    StudioUndo.apply(workspace, undoManager: undoManager)
    await workspace.batchTask?.value
    undoManager.endUndoGrouping()
    #expect(workspace.studio.steps.count == 2)
    #expect(undoManager.canUndo)
    undoManager.undo()
    #expect(workspace.studio.steps.count == 1)
  }
}
