import AstroStackApp
import Foundation
import ImageKit
import ProcessKit
import RenderKit
import Testing

/// The histories beside the combined image (cards 0119, 0159): compare with another history's
/// head, a branch's own undo / redo and outputs, the stretch each history keeps; and the side
/// column in the states an edit leaves it in.
extension StudioWorkspaceModelTests {
  @Test("compare with a branch's head; a branch's undo, redo and outputs", .scratchDirectory)
  func testOtherHistories_CompareUndoRedo() throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.workspace(opened, bundle: BranchTests.bundle())
    let studio = workspace.studio
    let other = try #require(workspace.comparable.first)

    try workspace.compare(with: other)
    #expect(workspace.comparingWith == other && workspace.viewer.reference != nil)
    try workspace.compare(with: nil)
    #expect(workspace.comparingWith == nil && workspace.viewer.reference == nil)

    let branch = StudioSelection.branch("Ha")
    try studio.apply(DenoiseProcess.id, params: ParamSet(schema: DenoiseProcess.schema), on: branch)
    #expect(try studio.output(ofStep: 0, on: branch).width > 0)
    #expect(throws: HistoryError.self) { try studio.output(ofStep: 0, on: .branch("nope")) }
    try studio.undo(on: branch)
    #expect(studio.canRedo(on: branch) && !studio.canRedo(on: .branch("nope")))
    try studio.redo(on: branch)
    #expect(!studio.canRedo(on: branch) && studio.canUndo)
  }

  @Test("each history keeps its own stretch, put back when shown again", .scratchDirectory)
  func testSelection_KeepsItsStretch() throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.workspace(opened, bundle: BranchTests.bundle())
    workspace.choose(StretchProcess.id)
    workspace.viewer.model.linked = true

    workspace.select(.branch("Ha"))
    #expect(!workspace.viewer.model.linked, "a first visit starts unlinked, on auto")
    workspace.select(.main)

    #expect(workspace.viewer.model.linked, "the combined image's stretch is back")
  }

  @Test(
    "the side column after an Apply that changed nothing, suspended, mid-compare",
    .scratchDirectory)
  func testSideColumn_States() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try await Self.applied(SaturationProcess.id, opened)
    #expect(workspace.appliedNothing && workspace.isPreviewSuspended)
    try workspace.compare(toStep: 0)

    let entries = AccessibilityAuditTests.entries(StudioSideView(model: workspace))

    #expect(Set(entries.map(\.id)).contains("fr.astrostack.stage.studio.step.0.compare"))
    #expect(AccessibilityAudit.problems(entries) == [])
  }
}

extension StudioWorkspaceModelTests {
  @Test("a revise refused by the runner says why and moves nothing", .scratchDirectory)
  func testReviseStep_FailureSaid() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let studio = try StudioModelTests.model(opened)
    try studio.apply(GeometryProcess.id, params: ParamSet(schema: GeometryProcess.schema))
    try studio.apply(
      SaturationProcess.id, params: ParamSet(schema: SaturationProcess.schema),
      mask: Self.halfMask(studio))
    let workspace = try StudioWorkspaceModel(studio: studio, base: [.color])
    let before = studio.steps
    var flip = ParamSet(schema: GeometryProcess.schema)
    try flip.set("flipV", .flag(true))

    await StudioUndo.reviseStep(
      workspace, step: 1, params: flip, on: StudioUndoRunTests.undoManager())

    #expect(workspace.failure != nil && studio.steps == before, "maskMoved: nothing moved")
  }

  @Test(
    "the plate solve's offer follows the catalogue object; another panel ignores it",
    .scratchDirectory)
  func testCatalogueOfferChanged() throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.workspace(opened, bundle: StudioModelTests.bundle())
    workspace.choose(StretchProcess.id)
    let stretchOffers = workspace.panel?.suggestions
    workspace.catalogueOfferChanged()
    #expect(workspace.panel?.suggestions == stretchOffers)

    workspace.choose(PlateSolveProcess.id)
    workspace.catalogueOfferChanged()
    #expect(workspace.panel?.type.id == PlateSolveProcess.id)
  }

  @Test("a retired workspace drops its moves from the undo manager", .scratchDirectory)
  func testRetire_DropsMoves() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.edited(opened)
    let undoManager = StudioUndoRunTests.undoManager()
    workspace.editStep(1)
    try #require(workspace.panel).set("targetBackground", .number(0.4))
    await StudioUndo.applyEdit(workspace, on: undoManager)
    #expect(undoManager.canUndo)

    workspace.retire()

    #expect(workspace.isRetired && !undoManager.canUndo)
  }
}
