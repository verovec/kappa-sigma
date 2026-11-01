import AstroStackApp
import Foundation
import ProcessKit
import TestSupport
import Testing

/// Card 0157: a revise is one ⌘Z, which puts the chain it replaced back (a history version,
/// nothing recomputed), and one ⇧⌘Z; it is refused with its reason when it cannot be made.
extension StudioUndoRunTests {
  /// A four-step pipeline run, then step 1 (stretch) revised with another target background.
  struct Revised {
    let workspace: StudioWorkspaceModel
    let sidebar: PipelineSidebarModel
    let undoManager: ProjectUndoManager
    /// The steps and the head before the revise.
    let before: [History.Step]
    let head: [[Float]]
  }

  static func revised(_ opened: StudioModelTests.Opened) async throws -> Revised {
    let (workspace, sidebar) = try PipelineSidebarModelTests.sidebar(
      opened, try PipelineSidebarModelTests.fourSteps())
    let undoManager = Self.undoManager()
    await sidebar.run(undoManager: undoManager)
    let before = workspace.studio.steps
    let head = workspace.studio.head.planes
    await StudioUndo.reviseStep(
      workspace, step: 1, params: try StudioModelTests.stretch(target: 0.4), on: undoManager)
    return Revised(
      workspace: workspace, sidebar: sidebar, undoManager: undoManager, before: before, head: head)
  }

  @Test("testUndoRevise_RestoresOldChain", .scratchDirectory)
  func testUndoRevise_RestoresOldChain() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let revised = try await Self.revised(opened)
    let (workspace, sidebar, undoManager) = (
      revised.workspace, revised.sidebar, revised.undoManager
    )
    let (before, head) = (revised.before, revised.head)
    let recipe = try PipelineSidebarModelTests.fourSteps().steps[1].recipe
    #expect(workspace.failure == nil && workspace.studio.steps.map(\.file) != before.map(\.file))
    #expect(
      sidebar.pipeline.steps[1].recipe.params != recipe.params, "the column has the new values")
    #expect(undoManager.undoActionName == String(localized: .app("Revise Step")))

    undoManager.undo()

    #expect(workspace.studio.steps == before, "the same steps, the same files")
    #expect(workspace.studio.head.planes == head)
    #expect(sidebar.pipeline.steps[1].recipe == recipe, "and the column's recipe")
    #expect(Self.ids(workspace) == Self.all)
  }

  @Test("testRedoRevise_RestoresNewChain", .scratchDirectory)
  func testRedoRevise_RestoresNewChain() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let fixture = try await Self.revised(opened)
    let (workspace, undoManager) = (fixture.workspace, fixture.undoManager)
    let revised = workspace.studio.steps
    let head = workspace.studio.head.planes
    undoManager.undo()

    undoManager.redo()

    #expect(workspace.studio.steps == revised && workspace.studio.head.planes == head)
    undoManager.undo()
    undoManager.redo()
    #expect(workspace.studio.steps == revised, "each ⌘Z / ⇧⌘Z is one swap")
    #expect(workspace.studio.session.history.versions.count == 1)
  }

  enum Refusal: String, CaseIterable, Sendable {
    case outOfRange, branch, toolStep, running
  }

  @Test(
    "testReviseStep_Refused: running, a branch shown, out of range, a host-tool step",
    .scratchDirectory, arguments: Refusal.allCases)
  func testReviseStep_Refused(_ refusal: Refusal) async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let during = BackgroundProcessTests.During()
    let bundle = refusal == .branch ? BranchTests.bundle() : StudioModelTests.bundle()
    let workspace =
      refusal == .running
      ? try BackgroundProcessTests.workspace(
        opened, tool: BackgroundProcessTests.tool(during: during))
      : try StudioWorkspaceModelTests.workspace(opened, bundle: bundle)
    let undoManager = Self.undoManager()
    await Self.apply(StretchProcess.id, workspace, undoManager)
    var index = 1
    var params = try StudioModelTests.stretch(target: 0.4)
    switch refusal {
    case .outOfRange: index = 5
    case .branch: workspace.select(.branch("Ha"))
    case .toolStep:
      try workspace.studio.apply(
        StarSeparation.id, params: ParamSet(schema: StarSeparation.schema),
        result: workspace.studio.head, outputs: [.starless: workspace.studio.head])
      (index, params) = (2, ParamSet(schema: StarSeparation.schema))
    case .running: break
    }
    let before = workspace.studio.steps
    let refused = Recorded<Bool>()
    if refusal == .running {
      // `reviseStep` asks this first: while the tool runs, it refuses.
      during.set {
        refused.append(StudioUndo.reviseRefusal(workspace, step: index, params: params) != nil)
      }
      workspace.choose(BackgroundExtractionProcess.id)
      let done = Recorded<Bool>()
      workspace.startTool { done.append($0) }
      while done.all.isEmpty { await Task.yield() }
      #expect(refused.all == [true], "refused while the tool ran")
      return
    }

    await StudioUndo.reviseStep(workspace, step: index, params: params, on: undoManager)

    #expect(workspace.failure != nil, "the reason is shown")
    #expect(workspace.studio.steps == before && workspace.studio.session.history.versions.isEmpty)
    #expect(undoManager.undoActionName != String(localized: .app("Revise Step")))
  }
}

extension StudioUndoRunTests {
  @Test("the version labels say which chain each holds, after ⌘Z and ⇧⌘Z", .scratchDirectory)
  func testRevise_VersionLabels() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let fixture = try await Self.revised(opened)
    let history = fixture.workspace.studio.session.history
    let before = String(localized: .app("Before revising step 2"))
    let revised = String(localized: .app("Revised step 2"))
    #expect(history.versions.map(\.label) == [before])

    fixture.undoManager.undo()
    #expect(history.versions.map(\.label) == [revised], "the chain put aside is the revised one")
    fixture.undoManager.redo()
    #expect(history.versions.map(\.label) == [before])
  }

  @Test("a column that plans other processes keeps its recipes on a revise", .scratchDirectory)
  func testRevise_ColumnNotFollowing_Untouched() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let fixture = try await Self.revised(opened)
    let other = Pipeline(
      name: "other",
      steps: [
        try PipelineSidebarModelTests.step(ChannelCombinationProcess.self),
        try PipelineSidebarModelTests.step(CurvesProcess.self),
      ])
    fixture.sidebar.show(other)
    await StudioUndo.reviseStep(
      fixture.workspace, step: 1, params: try StudioModelTests.stretch(target: 0.3),
      on: fixture.undoManager)
    #expect(fixture.sidebar.pipeline.steps.map(\.recipe) == other.steps.map(\.recipe))
  }
}

extension StudioUndoRunTests {
  @Test("a label recorded in French still names its chain under English", .scratchDirectory)
  func testRevise_LabelInAnotherLanguage() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let studio = try StudioModelTests.fourApplied(opened)
    var french: LocalizedStringResource = .app("Before revising step 2")
    french.locale = Locale(identifier: "fr")
    let history = studio.session.history
    try await history.revise(from: 1, label: String(localized: french)) { revised in
      try revised.apply(
        processID: StretchProcess.id, params: try StudioModelTests.stretch(target: 0.3),
        result: revised.current)
    }
    _ = try studio.restoreVersion(try #require(history.versions.last).id)
    #expect(history.versions.last?.label == String(localized: .app("Revised step 2")))
  }
}
