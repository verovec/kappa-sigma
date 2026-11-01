import AstroStackApp
import Foundation
import Metal
import ProcessKit
import RenderKit
import TestSupport
import Testing

/// The export form's folder (card 0151): the base with `~`, the sub-path template, and the
/// resolved path — the one `export()` writes into (R2).
@MainActor
@Suite(
  "ExportForm — base, template and the resolved folder shown",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
struct ExportFormTests {
  @Test(
    "testShowsResolvedPath: base with ~, template, resolved = what export() writes",
    .scratchDirectory)
  func testShowsResolvedPath() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let model = try ExportStageModelTests.model(
      opened, studio: try StudioModelTests.model(opened),
      services: try ExportStageModelTests.services())

    // Shown with ~ for the home folder (never written: a path under the real home).
    model.base = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Pictures/Astro")
    #expect(ExportForm.shown(model.base) == "~/Pictures/Astro")
    #expect(ExportForm.resolved(model) == "~/Pictures/Astro/M31/run1/2026-10-22-120000")

    // Under the scratch folder, the path shown is the folder the files land in.
    let base = try ScratchDirectory.url.appendingPathComponent("Deliverables")
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    model.base = base
    model.template = "{object}/{stack}"
    let shown = try #require(ExportForm.resolved(model))
    await model.export()
    #expect(model.failure == nil)
    let written = try #require(model.written.first).deletingLastPathComponent()
    #expect(ExportForm.shown(written) == shown && shown.hasSuffix("Deliverables/M31/run1"))
    #expect(try opened.package.store.exports(stackID: opened.stackID).first?.folder == written.path)

    // A template that names no folder shows why, in the form's colours.
    model.template = "{nope}"
    #expect(ExportForm.resolved(model) == nil && model.folderRefusal != nil)
    let entries = AccessibilityAuditTests.entries(ExportForm(model: model))
    #expect(AccessibilityAudit.problems(entries) == [])
    let ids = Set(entries.map(\.id))
    #expect(
      ids.isSuperset(of: [
        "fr.astrostack.stage.export.folder", "fr.astrostack.stage.export.folder.remember",
        "fr.astrostack.stage.export.folder.template",
      ]), "\(ids.sorted())")
  }
}
