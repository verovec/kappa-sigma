import AstroStackApp
import Foundation
import ImageKit
import Metal
import ProcessKit
import TestSupport
import Testing

/// Card 0187: a chain preview yields the main actor between its steps and, cancelled, shows
/// nothing — the window keeps answering while a long chain renders, and a drag's stale render
/// never lands after the next one started.
@MainActor
@Suite(
  "StudioWorkspaceModel — the chain preview yields and is cancellable",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
struct StudioWorkspaceModelPreviewTests {
  /// A workspace with two stretches applied after the combination, the first one being edited:
  /// its chain preview renders two steps.
  static func editingWorkspace(_ opened: StudioModelTests.Opened) async throws
    -> StudioWorkspaceModel
  {
    let workspace = try StudioWorkspaceModelTests.workspace(
      opened, bundle: StudioModelTests.bundle())
    for target in [0.2, 0.3] {
      workspace.choose(StretchProcess.id)
      try #require(workspace.panel).set("targetBackground", .number(target))
      await workspace.previewNow()
      try workspace.apply()
    }
    #expect(workspace.studio.steps.count == 3)
    workspace.choose(StretchProcess.id, params: workspace.studio.steps[1].params)
    workspace.editing = 1
    try #require(workspace.panel).set("targetBackground", .number(0.25))
    return workspace
  }

  @Test("testPreview_YieldsTheMainActorBetweenChainSteps", .scratchDirectory)
  func testPreview_YieldsTheMainActorBetweenChainSteps() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try await Self.editingWorkspace(opened)
    let order = Order()

    let chain = Task { @MainActor in
      await workspace.previewNow()
      order.events.append("rendered")
    }
    // Queued behind the chain on the main actor: runs only if the chain lets go between steps.
    let meanwhile = Task { @MainActor in order.events.append("meanwhile") }
    await chain.value
    await meanwhile.value

    #expect(order.events == ["meanwhile", "rendered"])
    #expect(workspace.isPreviewing && workspace.chainStoppedBefore == nil)
  }

  /// The next value cancels the chain in flight: its stale image never lands after the new one.
  @Test("testPreview_NextRenderCancelsTheOneInFlight", .scratchDirectory)
  func testPreview_NextRenderCancelsTheOneInFlight() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try await Self.editingWorkspace(opened)
    let panel = try #require(workspace.panel)

    let first = Task { @MainActor in await workspace.previewNow() }
    // The first chain has rendered its first step and let go: the value moves before its second.
    await Task.yield()
    panel.set("targetBackground", .number(0.4))
    await workspace.previewNow()
    let shown = workspace.viewer.model.image.planes
    await first.value

    let expected = try await workspace.studio.previewChain(from: 1, params: panel.params).image
    #expect(shown == expected.planes, "the new values show")
    #expect(workspace.viewer.model.image.planes == shown, "the cancelled chain landed nothing")
    #expect(workspace.isPreviewing && workspace.failure == nil, "a cancel is not a failure")
  }

  /// The order two main-actor tasks ran in.
  @MainActor
  final class Order {
    var events: [String] = []
  }
}
