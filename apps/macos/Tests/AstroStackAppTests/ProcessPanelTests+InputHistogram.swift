import AstroStackApp
import Foundation
import Metal
import ProcessKit
import TestSupport
import Testing

extension ProcessPanelTests {
  /// The processes whose default values sit on the histogram as handles.
  nonisolated static let handled: Set<String> = [LevelsProcess.id, StretchProcess.id]

  @Test(
    "every non-geometric panel draws the head's input histogram; handles only where values sit",
    .scratchDirectory, .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"),
    arguments: try ProcessRegistry.standard().ids)
  func testProcessPanel_inputHistogram_perProcess(processID: String) throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try StudioWorkspaceModelTests.workspace(
      opened, bundle: StudioModelTests.fullBundle())
    let type = try #require(try ProcessRegistry.standard().type(id: processID))
    workspace.choose(processID)
    let panel = try #require(workspace.panel)

    guard !(type is any GeometricProcess.Type) else {
      #expect(panel.sample == nil, "a moved grid has no input histogram to compare")
      return
    }
    let sample = try #require(panel.sample)
    #expect(sample.bins.count == workspace.studio.head.planes.count)
    #expect(panel.handles.isEmpty != Self.handled.contains(processID))
    if processID == StretchProcess.id {
      panel.set("mode", .choice("ghs"))
      #expect(panel.sample != nil && panel.handles.isEmpty, "GHS: the histogram, no handles")
    }
  }
}
