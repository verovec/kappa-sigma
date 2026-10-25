import AstroStackApp
import Foundation
import Metal
import ProcessKit
import ProjectKit
import TestSupport
import Testing

/// The Studio's workspace through the window (card 0087): a stack whose layers cannot be read
/// says so and shows its read-only layers; showing the Studio again retries the same stack.
@MainActor
@Suite(
  "Project window — the Studio workspace loads, fails, and is retried",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
struct ProjectWindowWorkspaceTests {
  /// Turns of the main actor until `done` holds (the workspace loads in a task the window owns).
  static func settle(_ done: () -> Bool) async {
    for _ in 0..<1_000_000 where !done() {
      await Task.yield()
    }
  }

  @Test("an unreadable layer is reported; retrying the shown stack loads it", .scratchDirectory)
  func testRetryAfterFailedLoad() async throws {
    let fixture = try ProjectTests.fixture()
    defer { try? fixture.project.close() }
    let output = fixture.project.url.appendingPathComponent("stacks/A")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    _ = try ProjectTests.writeBundle(in: output, runID: "A")
    _ = try fixture.project.store.addStack(
      bundlePath: "stacks/A", sourceIDs: [], paramsJSON: "{}", object: "M 31", scopeJSON: nil)
    // The header stays readable, the pixels do not.
    let layer = output.appendingPathComponent("rgb_base.fits")
    let intact = try Data(contentsOf: layer)
    try intact.prefix(2880).write(to: layer)

    let window = fixture.window
    window.refresh()
    window.select(.studio)
    await window.openStudio()
    #expect(window.studio?.source.runID == "A")
    await Self.settle { window.error != nil || window.workspace != nil }
    #expect(window.workspace == nil && window.error != nil, "the failure is said")

    try intact.write(to: layer)
    window.retryWorkspace()
    await Self.settle { window.workspace != nil }
    let workspace = try #require(window.workspace)
    #expect(workspace.studio.steps.map(\.processID) == ["channel-combination"])
    let ids = AccessibilityAuditTests.entries(ProjectWindowView(model: window)).map(\.id)
    #expect(ids.contains("fr.astrostack.stage.studio.undo"), "\(ids)")
    window.retryWorkspace()
    #expect(window.workspace === workspace, "a loaded workspace is kept")
  }
}

extension ProjectWindowWorkspaceTests {
  /// Card 0088: the Replay menu lists the project's other stacks; choosing one switches the
  /// Studio to it and runs the pipeline shown there once its working image is loaded.
  /// Two stacks of M 31 (runs A and B) recorded in the fixture's project.
  static func twoStacks(_ fixture: ProjectTests.Fixture) throws -> [ProjectStack] {
    var stacks: [ProjectStack] = []
    for runID in ["A", "B"] {
      let output = fixture.project.url.appendingPathComponent("stacks/\(runID)")
      try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
      _ = try ProjectTests.writeBundle(in: output, runID: runID)
      stacks.append(
        try fixture.project.store.addStack(
          bundlePath: "stacks/\(runID)", sourceIDs: [], paramsJSON: "{}", object: "M 31",
          scopeJSON: nil))
    }
    return stacks
  }

  @Test("Replay lists the other stacks and runs the pipeline on the chosen one", .scratchDirectory)
  func testReplayOnAnotherStack() async throws {
    let fixture = try ProjectTests.fixture()
    defer { try? fixture.project.close() }
    let stacks = try Self.twoStacks(fixture)
    let window = fixture.window
    window.refresh()
    window.selectStack(stacks[0].id)
    window.select(.studio)
    await window.openStudio()
    await Self.settle { window.workspace?.pipeline != nil }
    let sidebar = try #require(window.workspace?.pipeline)
    #expect(sidebar.pipeline.steps.map(\.recipe.processID) == ["channel-combination"])
    #expect(window.replayTargets.map(\.id) == [stacks[1].id])
    let state = { (action: Selector) in ProjectDocument.pipelineEnabled(action, in: window) }
    #expect(state(#selector(ProjectDocument.runPipeline(_:))))
    #expect(!state(#selector(ProjectDocument.continuePipeline(_:))), "no breakpoint")
    #expect(state(#selector(ProjectDocument.replayPipeline(_:))))
    #expect(!ProjectDocument.pipelineActions.contains(#selector(ProjectDocument.applyProcess(_:))))

    window.workspace?.choose(StretchProcess.id)
    await window.workspace?.previewNow()
    try window.workspace?.apply()
    #expect(sidebar.pipeline.steps.count == 2, "the Apply is a step of the pipeline")

    window.replayPipeline(on: stacks[1].id)
    await Self.settle {
      window.selectedStackID == stacks[1].id && window.workspace?.studio.steps.count == 2
    }
    let replayed = try #require(window.workspace)
    #expect(replayed.studio.steps.map(\.processID) == ["channel-combination", "stretch"])
    #expect(replayed.pipeline?.events == [.applied(1)])
  }
}
