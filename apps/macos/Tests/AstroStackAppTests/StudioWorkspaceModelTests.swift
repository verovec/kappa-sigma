import AstroStackApp
import Foundation
import ImageKit
import Metal
import ProcessKit
import TestSupport
import Testing

/// What the Studio pane drives (card 0087): the catalogue by stage with its greyed processes,
/// the panel of the chosen process, the live preview in the viewer, Apply / Undo / Redo, and
/// compare to an earlier step.
@MainActor
@Suite(
  "StudioWorkspaceModel — catalogue, panel, preview, apply, undo, compare",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
struct StudioWorkspaceModelTests {
  static func workspace(_ opened: StudioModelTests.Opened, bundle: PipelineBundle)
    throws -> StudioWorkspaceModel
  {
    let studio = try StudioModel(
      store: opened.package.store, stackID: opened.stackID, stackFolder: opened.folder,
      bundle: bundle)
    return try StudioWorkspaceModel(studio: studio, base: [.color])
  }

  @Test("the catalogue groups the registry by stage and greys what cannot run", .scratchDirectory)
  func testCatalogue() throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.workspace(opened, bundle: StudioModelTests.bundle())
    let entries = workspace.catalogue.flatMap(\.entries)
    #expect(Set(entries.map(\.id)) == Set(try ProcessRegistry.standard().ids))
    let stars = try #require(entries.first { $0.id == StarRecompositionProcess.id })
    #expect(stars.unavailable == .missing([.starless]))
    let stretch = try #require(entries.first { $0.id == StretchProcess.id })
    #expect(stretch.unavailable == nil)
    #expect(
      StudioCatalogueView.reason(.missing([.starless]), locale: Locale(identifier: "fr"))
        == "Il faut une couche sans étoiles")
  }

  @Test("choose, preview, apply, undo, redo, compare", .scratchDirectory)
  func testChoosePreviewApply() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.workspace(opened, bundle: StudioModelTests.bundle())
    let combined = workspace.viewer.model.image.planes
    #expect(workspace.studio.steps.count == 1)

    workspace.choose(StretchProcess.id)
    let panel = try #require(workspace.panel)
    #expect(panel.type.id == StretchProcess.id)
    panel.set("targetBackground", .number(0.2))
    await workspace.previewNow()
    #expect(workspace.isPreviewing && workspace.viewer.model.image.planes != combined)
    let previewed = workspace.viewer.model.image.planes

    try workspace.apply()
    #expect(workspace.studio.steps.map(\.processID) == ["channel-combination", "stretch"])
    #expect(!workspace.isPreviewing && workspace.viewer.model.image.planes == previewed)

    try workspace.undo()
    #expect(workspace.viewer.model.image.planes == combined)
    try workspace.redo()
    #expect(workspace.viewer.model.image.planes == previewed)

    try workspace.compare(toStep: 1)
    #expect(workspace.comparing == 1 && workspace.viewer.reference != nil)
    try workspace.undo()
    #expect(workspace.comparing == nil && workspace.viewer.reference == nil, "a step gone")
    try workspace.redo()
    try workspace.compare(toStep: 0)
    #expect(workspace.comparing == 0 && workspace.viewer.reference != nil)
    try workspace.compare(toStep: nil)
    #expect(workspace.viewer.reference == nil)
  }
}

extension StudioWorkspaceModelTests {
  /// A mask zero everywhere (a full luminosity range, inverted) lets nothing through: the
  /// preview and Apply both keep the head; without the mask the process shows.
  @Test("a mask applies to the preview and to Apply alike", .scratchDirectory)
  func testMask() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.workspace(opened, bundle: StudioModelTests.bundle())
    let combined = workspace.viewer.model.image.planes
    workspace.choose(StretchProcess.id)
    workspace.mask = Mask(
      source: .luminosityRange(low: 0, high: 1, softness: 0), inverted: true)
    await workspace.previewNow()
    #expect(workspace.viewer.model.image.planes == combined)
    try workspace.apply()
    #expect(workspace.studio.head.planes == combined)
    workspace.mask = nil
    try workspace.apply()
    #expect(workspace.studio.head.planes != combined)
  }
}
