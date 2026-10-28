import AstroStackApp
import Foundation
import Metal
import ProjectKit
import RenderKit
import StackKit
import SwiftUI
import TestSupport
import Testing

/// The Export stage through the window (card 0091): it opens with the Studio's workspace, its
/// controls are labelled and identified, and another stack replaces it.
@MainActor
@Suite(
  "Export stage pane — opened with the Studio, audited, replaced with the stack",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
struct ExportStagePaneTests {
  struct Opened {
    let project: ProjectPackage
    let window: ProjectWindowModel
  }

  /// A project with stacks `runs` (each a written bundle), its window on the Export stage with
  /// StarNet missing.
  static func open(
    _ runs: [String] = ["A"],
    tools: HostTools = HostTools { _ in .missing(path: "/usr/local/bin/starnet2") }
  ) async throws -> Opened {
    let scratch = try ScratchDirectory.url
    let project = try ProjectPackage.create(at: scratch.appendingPathComponent("M31.astrostack"))
    for run in runs {
      let output = project.url.appendingPathComponent("stacks/\(run)")
      try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
      _ = try ProjectTests.writeBundle(in: output, runID: run)
      _ = try project.store.addStack(
        bundlePath: "stacks/\(run)", sourceIDs: [], paramsJSON: "{}", imageRoles: ["RGB"])
    }
    let window = ProjectWindowModel(
      store: { project.store }, folder: { project.url },
      exports: try ExportStageModelTests.services(tools))
    window.select(.export)
    await window.openStudio()
    await ProjectWindowWorkspaceTests.settle { window.exportStage != nil || window.error != nil }
    return Opened(project: project, window: window)
  }

  @Test("the stage opens with the Studio's workspace; every control is labelled", .scratchDirectory)
  func testPaneAudited() async throws {
    let opened = try await Self.open()
    defer { try? opened.project.close() }
    let export = try #require(opened.window.exportStage)
    #expect(export.studio === opened.window.workspace?.studio)
    await export.separateStars()
    #expect(export.installCard != nil)
    await export.export()
    #expect(export.exports.count == 1)

    let entries = AccessibilityAuditTests.entries(
      ProjectWindowView(model: opened.window, projects: .empty))
    #expect(AccessibilityAudit.problems(entries) == [])
    let ids = Set(entries.map(\.id))
    let expected = [
      "fr.astrostack.stage.export.export", "fr.astrostack.stage.export.separate",
      "fr.astrostack.stage.export.file.final", "fr.astrostack.stage.export.format.png16",
      "fr.astrostack.stage.export.mirror", "fr.astrostack.stage.export.name",
      "fr.astrostack.stage.export.folder", "fr.astrostack.parameter.export.starColour.slider",
      "fr.astrostack.install.starnet2.install",
    ]
    #expect(ids.isSuperset(of: expected), "\(ids.sorted())")
    let sheet = AccessibilityAuditTests.entries(StarSeparationSheet(model: export))
    #expect(sheet.map(\.id) == ["fr.astrostack.stage.export.cancelSeparation"])
  }

  @Test("the record list shows each export with Reveal in Finder", .scratchDirectory)
  func testRecordListed() async throws {
    let opened = try await Self.open()
    defer { try? opened.project.close() }
    let export = try #require(opened.window.exportStage)
    await export.export()
    let record = try #require(export.exports.first)

    // A List keeps its rows' preferences: the list is hosted for its layout, each row alone.
    _ = AccessibilityAuditTests.entries(ExportRecordList(model: export))
    let entries = AccessibilityAuditTests.entries(ExportRecordRow(record: record, model: export))
    #expect(entries.map(\.id) == ["fr.astrostack.stage.export.reveal.\(record.id)"])
    #expect(opened.window.statuses[.export] == .done)
  }

  @Test(
    "another stack replaces the Export stage; without a stack the pane is empty", .scratchDirectory)
  func testStackChangeReplacesStage() async throws {
    let opened = try await Self.open(["A", "B"])
    defer { try? opened.project.close() }
    let first = try #require(opened.window.exportStage)
    let stacks = try opened.project.store.stacks()
    #expect(first.stack.id == stacks.last?.id)

    opened.window.selectStack(stacks.first?.id)
    #expect(opened.window.exportStage == nil)
    await opened.window.openStudio()
    await ProjectWindowWorkspaceTests.settle { opened.window.exportStage != nil }
    #expect(opened.window.exportStage?.stack.id == stacks.first?.id)

    let empty = try ProjectPackage.create(
      at: ScratchDirectory.url.appendingPathComponent("Empty.astrostack"))
    defer { try? empty.close() }
    let window = ProjectWindowModel(store: { empty.store })
    window.select(.export)
    let ids = AccessibilityAuditTests.entries(ProjectWindowView(model: window, projects: .empty))
      .map(\.id)
    #expect(ids == ["fr.astrostack.help.stage.export"])
  }
}
