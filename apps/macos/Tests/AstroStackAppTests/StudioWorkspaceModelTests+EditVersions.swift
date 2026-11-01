import AstroStackApp
import Foundation
import ImageKit
import ProcessKit
import TestSupport
import Testing

/// Card 0159: the Versions menu (compare, an undoable restore the column follows, a drop that
/// frees the files) and the recorded masks ▶ Run keeps for the steps a revise left pending.
extension StudioWorkspaceModelTests {
  @Test(
    "testVersionsMenu_RestoreAndDrop: compare, an undoable restore, drop frees the files",
    .scratchDirectory)
  func testVersionsMenu_RestoreAndDrop() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.edited(opened)
    let undoManager = StudioUndoRunTests.undoManager()
    let before = workspace.studio.steps
    workspace.editStep(1)
    try #require(workspace.panel).set("targetBackground", .number(0.4))
    await StudioUndo.applyEdit(workspace, on: undoManager)
    let revised = workspace.studio.steps
    let version = try #require(workspace.versions.last)
    #expect(workspace.bytes(ofVersion: version.id) > 0)

    workspace.toggleCompare(version: version.id)
    #expect(workspace.comparingVersion == version.id && workspace.viewer.reference != nil)

    undoManager.undo()
    #expect(workspace.comparingVersion == nil, "a ⌘Z ends a version's compare")
    undoManager.redo()
    let current = try #require(workspace.versions.last)
    StudioUndo.restoreVersion(workspace, current.id, on: undoManager)
    #expect(workspace.studio.steps == before && workspace.failure == nil)
    #expect(workspace.comparingVersion == nil, "the compare ends with the move")
    #expect(undoManager.undoActionName == String(localized: .app("Restore Version")))
    undoManager.undo()
    #expect(workspace.studio.steps == revised, "⌘Z puts the revised chain back")

    let kept = try #require(workspace.versions.last)
    let directory = workspace.studio.session.history.directory
    let files = kept.steps.map { directory.appendingPathComponent($0.file).path }
    StudioUndo.dropVersion(workspace, kept.id, on: undoManager)

    #expect(workspace.versions.isEmpty)
    #expect(!undoManager.canUndo, "no ⌘Z left to swap the dropped version back")
    #expect(files.allSatisfy { !FileManager.default.fileExists(atPath: $0) })
    #expect(workspace.studio.steps == revised)
  }

  @Test("a step with no panel (StarNet's) is refused with its reason", .scratchDirectory)
  func testEditStep_NoPanelRefused() throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let studio = try StudioModelTests.model(opened)
    try studio.apply(
      StarSeparation.id, params: ParamSet(schema: StarSeparation.schema), result: studio.head,
      outputs: [.starless: studio.head])
    let workspace = try StudioWorkspaceModel(studio: studio, base: [.color])

    workspace.editStep(1)

    #expect(workspace.editing == nil && workspace.panel == nil)
    #expect(workspace.failure != nil)
  }

  @Test("Apply change on a host-tool step is greyed with the revise's reason", .scratchDirectory)
  func testApplyEdit_ToolStepGreyed() throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.edited(opened)

    workspace.editStep(3)
    #expect(workspace.applyEditRefusal() != nil)
    workspace.editStep(1)
    #expect(workspace.applyEditRefusal() == nil)
  }

  /// Combination, stretch, a background extraction, a masked saturation; the column plans them.
  static func pending(_ opened: StudioModelTests.Opened, first: (String, ParamSet)) async throws
    -> (StudioWorkspaceModel, PipelineSidebarModel)
  {
    let ids = [
      ChannelCombinationProcess.id, first.0, BackgroundExtractionProcess.id, SaturationProcess.id,
    ]
    let pipeline = Pipeline(
      name: "p",
      steps: try ids.map { id in
        let type = try #require(try ProcessRegistry.standard().type(id: id))
        return PipelineStep(recipe: Recipe(processID: id, params: ParamSet(schema: type.schema)))
      })
    let (workspace, sidebar) = try PipelineSidebarModelTests.sidebar(opened, pipeline)
    let studio = workspace.studio
    try studio.apply(first.0, params: first.1)
    try studio.apply(
      BackgroundExtractionProcess.id, params: ParamSet(schema: BackgroundExtractionProcess.schema),
      result: studio.head)
    try studio.apply(
      SaturationProcess.id, params: ParamSet(schema: SaturationProcess.schema),
      mask: Self.halfMask(studio))
    return (workspace, sidebar)
  }

  @Test("a version ▶ Run still needs the masks of is not dropped", .scratchDirectory)
  func testDropVersion_RefusedWhileRunNeedsItsMasks() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let (workspace, _) = try await Self.pending(
      opened, first: (StretchProcess.id, try StudioModelTests.stretch(target: 0.2)))
    try await workspace.studio.reviseStep(1, params: try StudioModelTests.stretch(target: 0.4))
    let version = try #require(workspace.versions.last)

    #expect(StudioUndo.dropRefusal(workspace, version.id) != nil)
    StudioUndo.dropVersion(workspace, version.id, on: StudioUndoRunTests.undoManager())
    #expect(workspace.versions.count == 1 && workspace.failure != nil)
  }

  @Test("▶ Run refuses recorded masks a pixel-moving revise would misplace", .scratchDirectory)
  func testPendingMasks_MovedPixelsRefused() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let (workspace, sidebar) = try await Self.pending(
      opened, first: (GeometryProcess.id, ParamSet(schema: GeometryProcess.schema)))
    var flip = ParamSet(schema: GeometryProcess.schema)
    try flip.set("flipV", .flag(true))
    try await workspace.studio.reviseStep(1, params: flip)
    let planned = sidebar.pipeline.steps.map(\.recipe.processID)

    #expect(throws: PipelineError.maskMoved(step: 3)) {
      try workspace.studio.pendingMasks(from: 2, planned: planned)
    }
  }

  @Test(
    "a restore gives the column the restored steps' values; ⌘Z puts them back",
    .scratchDirectory)
  func testRestoreVersion_ColumnFollows() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let (workspace, sidebar) = try await Self.pending(
      opened, first: (StretchProcess.id, try StudioModelTests.stretch(target: 0.2)))
    let undoManager = StudioUndoRunTests.undoManager()
    await StudioUndo.reviseStep(
      workspace, step: 1, params: try StudioModelTests.stretch(target: 0.4), on: undoManager)
    let revised = sidebar.pipeline.steps[1].recipe
    let version = try #require(workspace.versions.last)

    StudioUndo.restoreVersion(workspace, version.id, on: undoManager)

    let restored = Recipe(processID: StretchProcess.id, params: workspace.studio.steps[1].params)
    #expect(sidebar.pipeline.steps[1].recipe == restored && restored != revised)
    undoManager.undo()
    #expect(sidebar.pipeline.steps[1].recipe == revised)
  }

  @Test(
    "a version is not dropped while its masks cannot be checked (a moving revise)",
    .scratchDirectory)
  func testDropRefusal_WhenTheCheckThrows() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let (workspace, _) = try await Self.pending(
      opened, first: (GeometryProcess.id, ParamSet(schema: GeometryProcess.schema)))
    var flip = ParamSet(schema: GeometryProcess.schema)
    try flip.set("flipV", .flag(true))
    try await workspace.studio.reviseStep(1, params: flip)

    #expect(StudioUndo.dropRefusal(workspace, try #require(workspace.versions.last).id) != nil)
  }

  @Test("a version is compared beside the combined image only", .scratchDirectory)
  func testCompareVersion_RefusedOnBranch() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.workspace(opened, bundle: BranchTests.bundle())
    try workspace.studio.apply(StretchProcess.id, params: try StudioModelTests.stretch(target: 0.2))
    try await workspace.studio.reviseStep(1, params: try StudioModelTests.stretch(target: 0.4))
    let version = try #require(workspace.versions.last)
    workspace.select(.branch("Ha"))

    workspace.toggleCompare(version: version.id)

    #expect(workspace.comparingVersion == nil && workspace.failure != nil)
  }
}
