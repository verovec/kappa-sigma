import AstroStackApp
import Foundation
import ImageKit
import ProcessKit
import Testing

/// Card 0158: while a step is edited (`editing`, set by 0159), the preview draws the chain —
/// step k with the panel's values, then the steps after it — up to the first host tool, which
/// the banner names; without it the head preview is today's.
extension StudioWorkspaceModelTests {
  /// The workspace over the studio of `opened` with stretch, curves, saturation applied, the
  /// stretch panel open at a new target.
  static func editingStretch(_ studio: StudioModel) throws -> StudioWorkspaceModel {
    let workspace = try StudioWorkspaceModel(studio: studio, base: [.color])
    workspace.choose(StretchProcess.id)
    try #require(workspace.panel).set("targetBackground", .number(0.4))
    return workspace
  }

  @Test("testEditingPreviewDrawsChain", .scratchDirectory)
  func testEditingPreviewDrawsChain() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let studio = try StudioModelTests.fourApplied(opened)
    let workspace = try Self.editingStretch(studio)
    let params = try #require(workspace.panel).params

    workspace.editing = 1
    await workspace.settlePreview()

    let chain = try await studio.previewChain(from: 1, params: params)
    #expect(workspace.isPreviewing && workspace.chainStoppedBefore == nil)
    #expect(workspace.viewer.model.image.planes == chain.image.planes)
    let head = try studio.preview(StretchProcess.id, params: params)
    #expect(workspace.viewer.model.image.planes != head.planes, "not the head's preview")
    #expect(workspace.chainStopNotice(locale: Locale(identifier: "en")) == nil)
    #expect(studio.steps.count == 4, "a preview records nothing")
  }

  @Test("the chain stops before a host tool and the banner names it", .scratchDirectory)
  func testEditingPreview_StopsBeforeToolSaysSo() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let studio = try StudioModelTests.model(opened)
    try studio.apply(StretchProcess.id, params: ParamSet(schema: StretchProcess.schema))
    try studio.apply(
      StarSeparation.id, params: ParamSet(schema: StarSeparation.schema), result: studio.head,
      outputs: [.starless: studio.head])
    try studio.apply(SaturationProcess.id, params: ParamSet(schema: SaturationProcess.schema))
    let workspace = try Self.editingStretch(studio)

    workspace.editing = 1
    await workspace.settlePreview()

    #expect(workspace.chainStoppedBefore == 2)
    let notice = { (language: String) in
      try String(
        localized: #require(workspace.chainStopNotice(locale: Locale(identifier: language))))
    }
    #expect(
      try notice("fr")
        == "Aperçu arrêté avant Séparation des étoiles (StarNet) (étape 3)"
        + " — recalculé à la validation")
    #expect(
      try notice("en")
        == "Preview stopped before Star separation (StarNet) (step 3) — computed when applied")

    workspace.editing = nil
    await workspace.settlePreview()
    #expect(workspace.chainStoppedBefore == nil, "the banner leaves with the edit")
  }

  @Test("testNoEditing_PreviewUnchanged", .scratchDirectory)
  func testNoEditing_PreviewUnchanged() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let studio = try StudioModelTests.fourApplied(opened)
    let workspace = try Self.editingStretch(studio)
    let params = try #require(workspace.panel).params

    await workspace.previewNow()

    #expect(workspace.editing == nil && workspace.chainStoppedBefore == nil)
    let head = try studio.preview(StretchProcess.id, params: params)
    #expect(workspace.viewer.model.image.planes == head.planes, "the head's preview")
  }

  @Test(
    "while a step is edited Apply records nothing on the head; a move ends the edit",
    .scratchDirectory)
  func testEditing_ApplyRecordsNothing_UndoEndsEdit() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let studio = try StudioModelTests.fourApplied(opened)
    let workspace = try Self.editingStretch(studio)
    workspace.editing = 1
    await workspace.settlePreview()

    try workspace.apply()
    #expect(studio.steps.count == 4, "the chain shown is not the panel's values on the head")

    try workspace.undo()
    #expect(workspace.editing == nil && workspace.chainStoppedBefore == nil)
  }

  @Test(
    "another process's panel previews on the head, never on the edited step's schema",
    .scratchDirectory)
  func testEditing_OtherProcessPanel_PreviewsHead() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let studio = try StudioModelTests.fourApplied(opened)
    let workspace = try Self.editingStretch(studio)
    let params = try #require(workspace.panel).params

    workspace.editing = 2  // curves
    await workspace.settlePreview()

    let head = try studio.preview(StretchProcess.id, params: params)
    #expect(workspace.viewer.model.image.planes == head.planes)
    try workspace.apply()
    #expect(studio.steps.count == 5, "what is shown on the head is what Apply records")
  }

  @Test("showing a layer's branch ends the edit and drops the cached input", .scratchDirectory)
  func testSelectBranch_EndsEdit() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.workspace(opened, bundle: BranchTests.bundle())
    try workspace.studio.apply(StretchProcess.id, params: ParamSet(schema: StretchProcess.schema))
    workspace.choose(StretchProcess.id)
    workspace.editing = 1
    await workspace.settlePreview()
    #expect(workspace.studio.session.chainInputFiles != nil)
    let branch = try #require(workspace.selections.first { $0 != .main })

    workspace.select(branch)

    #expect(workspace.editing == nil && workspace.studio.session.chainInputFiles == nil)
  }

  @Test("closing the panel ends the edit and drops the chain's cached input", .scratchDirectory)
  func testClosePanel_EndsEdit() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let studio = try StudioModelTests.fourApplied(opened)
    let workspace = try Self.editingStretch(studio)
    workspace.editing = 1
    await workspace.settlePreview()
    #expect(studio.session.chainInputFiles != nil)

    workspace.closePanel()

    #expect(workspace.editing == nil && studio.session.chainInputFiles == nil)
  }

  @Test("an edited host-tool step never runs as a new step on the head", .scratchDirectory)
  func testEditedToolStep_StartToolRefused() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let studio = try StudioModelTests.model(opened)
    let solve = ParamSet(schema: PlateSolveProcess.schema)
    try studio.apply(PlateSolveProcess.id, params: solve, result: studio.head)
    // A tool that would record a step: only the edited-step rule keeps it from running.
    let tool = StudioTool { image, _, _ in StudioToolResult(image: image, report: nil) }
    let workspace = try StudioWorkspaceModel(
      studio: studio, base: [.color], tools: [PlateSolveProcess.id: tool])
    workspace.choose(PlateSolveProcess.id, params: solve)
    workspace.editing = 1

    let recorded = await withCheckedContinuation { done in
      workspace.startTool { done.resume(returning: $0) }
    }

    #expect(!recorded && studio.steps.count == 2)
  }
}
