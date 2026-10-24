import AppKit
import AstroStackApp
import Foundation
import ProjectKit
import RenderKit
import StackKit
import SwiftUI
import TestSupport
import Testing

/// What the project's stacks take on disk (card 0114): a finished run trimmed to its bundle, the
/// Storage section's sizes and exports, Delete refused on the stack the Studio shows.
@MainActor
@Suite("Stack storage — trim, list and delete stacks in the project window")
struct StackStorageTests {
  /// `ProjectTests.fakeRun` that also leaves the intermediates and a master a real run writes.
  static func runLeavingIntermediates(_ seen: Recorded<PreprocessRequest>) -> RunServices.Run {
    let base = ProjectTests.fakeRun(seen)
    return { request in
      try? FileManager.default.createDirectory(
        at: request.output, withIntermediateDirectories: true)
      for name in ["aligned_RGB.fits", "combine_RGB.fits", "master_RGB.fits"] {
        try? Data(count: 4096).write(to: request.output.appendingPathComponent(name))
      }
      return base(request)
    }
  }

  @Test(
    "a finished run is trimmed to its bundle, the journal says so; the Studio marks it opened",
    .scratchDirectory)
  func testFinishedRunTrimmedAndOpened() async throws {
    let ran = Recorded<PreprocessRequest>()
    let fixture = try ProjectTests.fixture(run: Self.runLeavingIntermediates(ran))
    defer { try? fixture.project.close() }
    let window = fixture.window
    window.add(ImportRequest(paths: ["/c/M31-DB"]))
    window.startRun()
    await window.run?.settled()

    let folder = fixture.project.url.appendingPathComponent("stacks/\(ProjectTests.runID)")
    let left = try FileManager.default.contentsOfDirectory(atPath: folder.path)
    #expect(left.contains("master_RGB.fits") && left.contains("rgb_base.fits"))
    #expect(!left.contains("aligned_RGB.fits") && !left.contains("combine_RGB.fits"))
    let notes = window.run?.journal.map(\.text).filter { $0.hasPrefix("trimmed ") } ?? []
    #expect(notes.count == 2 && notes.allSatisfy { $0.contains("not read by the bundle") })

    let stack = try #require(try fixture.project.store.stacks().first)
    for _ in 0..<200 where window.workspace == nil { await Task.yield() }
    #expect(try fixture.project.store.stack(id: stack.id)?.openedAt != nil)
  }

  @Test("a folder whose bundle cannot be read is not trimmed: one warning line", .scratchDirectory)
  func testTrimFailureIsAWarning() async throws {
    let folder = try ScratchDirectory.url.appendingPathComponent("stacks/R1")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data(count: 16).write(to: folder.appendingPathComponent("aligned_RGB.fits"))
    let notes = await ProjectWindowModel.trimNotes(folder)
    #expect(notes.count == 1 && notes[0].hasPrefix("⚠ stack folder not trimmed"))
    let aligned = folder.appendingPathComponent("aligned_RGB.fits")
    #expect(FileManager.default.fileExists(atPath: aligned.path))
  }

  /// A saved project with a capture night and two stacks in `stacks/`, the first exported.
  static func project() throws -> (ProjectPackage, [ProjectStack]) {
    let project = try ProjectPackage.create(
      at: try ScratchDirectory.url.appendingPathComponent("M31.astrostack"))
    let store = project.store
    let night = try store.addSource(kind: .night, path: "/c/M31-DB")
    let stacks = try ["A", "B"].map { name in
      let stack = try store.addStack(
        bundlePath: "stacks/\(name)", sourceIDs: [night.id], paramsJSON: "{}",
        imageRoles: ["RGB", "Ha"])
      let folder = project.url.appendingPathComponent("stacks/\(name)")
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      _ = try ProjectTests.writeBundle(in: folder, runID: name)
      return stack
    }
    let image = try #require(try store.images(stackID: stacks[0].id).first)
    try store.addExport(
      stackID: stacks[0].id, imageID: image.id, headStepID: nil, folder: "/tmp/out",
      settingsJSON: "{}", files: ["final.png"])
    return (project, stacks)
  }

  @Test(
    "the Storage section lists each stack's size and exports; Delete removes one",
    .scratchDirectory)
  func testListAndDelete() async throws {
    let (project, stacks) = try Self.project()
    defer { try? project.close() }
    let window = StackLeftoversViewTests.window(project)
    window.refresh()
    await window.listStorage()
    #expect(window.storage.map(\.id) == stacks.map(\.id))
    #expect(window.storage.map(\.exports) == [1, 0])
    #expect(window.storage.allSatisfy { $0.bytes > 0 })

    window.selectStack(stacks[1].id)
    await window.deleteStack(stacks[1].id)
    #expect(window.error == nil)
    #expect(window.storage.map(\.id) == [stacks[0].id])
    #expect(window.stacks.map(\.id) == [stacks[0].id] && window.selectedStack?.id == stacks[0].id)
    let gone = project.url.appendingPathComponent("stacks/B")
    #expect(!FileManager.default.fileExists(atPath: gone.path))
  }

  @Test("the stack the Studio shows is refused, the reason shown", .scratchDirectory)
  func testOpenStackRefused() async throws {
    let (project, stacks) = try Self.project()
    defer { try? project.close() }
    let window = StackLeftoversViewTests.window(project)
    window.refresh()
    await window.openStudio()
    #expect(window.error == nil)
    #expect(window.openStackID == stacks[1].id)
    await window.deleteStack(stacks[1].id)
    #expect(window.error == .stackOpen)
    #expect(try project.store.stack(id: stacks[1].id) != nil)

    // A newer stack becomes « the latest » while the Studio still reads B: B stays refused.
    try project.store.addStack(bundlePath: "stacks/C", sourceIDs: [], paramsJSON: "{}")
    window.refresh()
    #expect(window.selectedStack?.bundlePath == "stacks/C")
    #expect(window.openStackID == stacks[1].id)
  }

  @Test(
    "the Données stage shows each stack's Delete…, in the interface language",
    .scratchDirectory, arguments: [("fr", "Supprimer…"), ("en", "Delete…")])
  func testRowsShown(_ language: String, label: String) async throws {
    let (project, stacks) = try Self.project()
    defer { try? project.close() }
    let window = StackLeftoversViewTests.window(project)
    window.refresh()
    await window.listStorage()
    window.select(.data)

    let entries = AccessibilityAuditTests.entries(
      ProjectWindowView(model: window), language: language)

    for stack in stacks {
      let delete = try #require(
        entries.first { $0.id == AccessibilityID.dataDeleteStack(stack.id).rawValue })
      #expect(delete.label == label)
    }
  }
}
