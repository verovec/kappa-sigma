import AstroStackApp
import Foundation
import ProjectKit
import RenderKit
import TestSupport
import Testing

/// The Stacking stage shows each stack folder no stack records, with Delete… (card 0113).
@MainActor
@Suite("Stack leftovers row — in the Stacking stage, fr and en")
struct StackLeftoversViewTests {
  /// A window over `project` whose import services never reach the host's library.
  static func window(_ project: ProjectPackage) -> ProjectWindowModel {
    ProjectWindowModel(
      store: { project.store }, folder: { project.url }, planning: { _ in ImportPlanningStub.empty }
    )
  }

  @Test(
    "a kept stack folder shows its Delete…, labelled in the interface language",
    .scratchDirectory, arguments: [("fr", "Supprimer…"), ("en", "Delete…")])
  func testRowShown(_ language: String, label: String) throws {
    let project = try ProjectPackage.create(
      at: try ScratchDirectory.url.appendingPathComponent("M31.astrostack"))
    defer { try? project.close() }
    let kept = project.url.appendingPathComponent("stacks/20261020_220000")
    try FileManager.default.createDirectory(at: kept, withIntermediateDirectories: true)
    try Data(count: 4096).write(to: kept.appendingPathComponent("master_G.fits"))
    let window = Self.window(project)
    window.select(.stacking)

    let entries = AccessibilityAuditTests.entries(
      ProjectWindowView(model: window), language: language)

    let delete = try #require(
      entries.first { $0.id == AccessibilityID.stackingDeleteLeftover("20261020_220000").rawValue })
    #expect(delete.label == label)
  }

  @Test("no row without a leftover", .scratchDirectory)
  func testNoRow() throws {
    let project = try ProjectPackage.create(
      at: try ScratchDirectory.url.appendingPathComponent("M31.astrostack"))
    defer { try? project.close() }
    let window = Self.window(project)
    window.select(.stacking)

    let ids = AccessibilityAuditTests.entries(ProjectWindowView(model: window)).map(\.id)

    #expect(ids.contains(AccessibilityID.stackingRun.rawValue), "the Stacking pane is shown")
    #expect(!ids.contains { $0.contains("deleteLeftover") })
  }
}
