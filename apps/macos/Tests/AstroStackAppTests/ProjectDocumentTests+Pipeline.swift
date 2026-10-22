import AppKit
import AstroStackApp
import Foundation
import Metal
import ProcessKit
import ProjectKit
import RenderKit
import TestSupport
import Testing

extension ProjectDocumentTests {
  /// Card 0088 through the document: on the Studio stage with a stack loaded, Run Pipeline
  /// (⌥⌘R) runs to the breakpoint and Continue (⌥⌘↩) finishes; the menu items follow.
  @Test(
    "Run and Continue Pipeline from the menu on a loaded stack", .scratchDirectory,
    .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
  func testPipelineCommandsOnStack() async throws {
    let url = try ScratchDirectory.url.appendingPathComponent("M31.astrostack")
    let package = try ProjectPackage.create(at: url)
    let output = url.appendingPathComponent("stacks/A")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    _ = try ProjectTests.writeBundle(in: output, runID: "A")
    _ = try package.store.addStack(
      bundlePath: "stacks/A", sourceIDs: [], paramsJSON: "{}", object: "M 31", scopeJSON: nil)
    try package.close()

    let document = try ProjectDocument(contentsOf: url, ofType: Self.type)
    defer { document.close() }
    document.makeWindowControllers()
    let window = try #require(document.windowModel)
    window.refresh()
    window.select(.studio)
    await window.openStudio()
    await ProjectWindowWorkspaceTests.settle { window.workspace?.pipeline != nil }
    let sidebar = try #require(window.workspace?.pipeline)
    var stop = PipelineStep(
      recipe: Recipe(processID: StretchProcess.id, params: ParamSet(schema: StretchProcess.schema)))
    stop.mode = .stop
    sidebar.show(Pipeline(name: "p", steps: sidebar.pipeline.steps + [stop]))

    func enabled(_ action: Selector) -> Bool {
      document.validateUserInterfaceItem(NSMenuItem(title: "", action: action, keyEquivalent: ""))
    }
    #expect(enabled(#selector(ProjectDocument.runPipeline(_:))))
    #expect(!enabled(#selector(ProjectDocument.continuePipeline(_:))))
    document.runPipeline(nil)
    await ProjectWindowWorkspaceTests.settle { sidebar.stoppedAt == 1 }
    #expect(enabled(#selector(ProjectDocument.continuePipeline(_:))))
    document.continuePipeline(nil)
    await ProjectWindowWorkspaceTests.settle { window.workspace?.studio.steps.count == 2 }
    #expect(window.workspace?.studio.steps.map(\.processID) == ["channel-combination", "stretch"])
    document.replayPipeline(nil)
    #expect(window.isChoosingReplay, "the chooser opens (no other stack: the item is off)")
    #expect(!enabled(#selector(ProjectDocument.replayPipeline(_:))))
  }
}
