import AppKit
import AstroStackApp
import Foundation
import Metal
import ProcessKit
import RenderKit
import SwiftUI
import TestSupport
import Testing

extension StudioViewsTests {
  /// Card 0090: the geometry panel shows « Use region » and the output's size instead of the
  /// mask row; every sentence it can show resolves in French.
  @Test("the geometry side column: Use region, no mask row, labelled", .scratchDirectory)
  func testGeometryColumn() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try StudioWorkspaceModelTests.workspace(
      opened, bundle: StudioModelTests.bundle())
    workspace.choose(GeometryProcess.id)
    await workspace.previewNow()
    let entries = AccessibilityAuditTests.entries(StudioSideView(model: workspace))
    let ids = Set(entries.map(\.id))
    #expect(ids.contains("fr.astrostack.stage.studio.geometry.useRegion"))
    #expect(!ids.contains("fr.astrostack.stage.studio.mask.source"))
    #expect(AccessibilityAudit.problems(entries) == [])

    let french = Locale(identifier: "fr")
    func words(_ resource: LocalizedStringResource) -> String {
      var resource = resource
      resource.locale = french
      return String(localized: resource)
    }
    #expect(words(GeometryExtras.solution(.moved)) == "La solution astrométrique suit les pixels.")
    #expect(GeometryExtras.reason(.notGeometry) == nil)
    let moved = "L’aperçu déplace les pixels : comparez une fois la géométrie appliquée"
    #expect(words(UserFacingError.movedPreview.message) == moved + " ou remise à zéro.")
    #expect(
      words(UserFacingError(StudioError.otherSize(step: 1)).message)
        == "L’étape 2 n’a pas la taille de l’image : elle ne peut pas être comparée.")
    #expect(
      try words(#require(GeometryExtras.reason(.noRegion)))
        == "Tracez d’abord une région dans le visualiseur.")
  }
}
