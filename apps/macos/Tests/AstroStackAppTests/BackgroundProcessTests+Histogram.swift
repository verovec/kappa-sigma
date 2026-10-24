import AstroStackApp
import Foundation
import ProcessKit
import RenderKit
import TestSupport
import Testing

extension BackgroundProcessTests {
  @Test(
    "« Show model » says the viewer counts the model; hiding it says image again",
    .scratchDirectory)
  func testShowModel_subjectIsTheModel() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.workspace(opened)
    workspace.choose(BackgroundExtractionProcess.id)
    #expect(await workspace.runTool())
    try workspace.toggleModel()
    #expect(workspace.showsModel && workspace.viewer.model.subject == .model)
    try workspace.toggleModel()
    #expect(!workspace.showsModel && workspace.viewer.model.subject == .image)
  }

  @Test(
    "on a colour head the panel knows its planes: the chosen engine's values show undisclosed",
    .scratchDirectory)
  func testEngineValuesPromotedOnColourHead() throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.workspace(opened)
    workspace.choose(BackgroundExtractionProcess.id)
    let panel = try #require(workspace.panel)
    #expect(panel.sample?.planes.count == 3)
    panel.set("engine", .choice("siril-rbf"))
    let shown = Set(panel.visibleSpecs.map(\.id))
    #expect(shown.isSuperset(of: BackgroundExtractionProcess.promoted(panel.params)))
  }
}
