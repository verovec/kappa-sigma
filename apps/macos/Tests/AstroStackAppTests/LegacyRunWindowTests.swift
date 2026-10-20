import AppKit
import AstroStackApp
import Foundation
import ImageKit
import Metal
import ProjectKit
import StackKit
import SwiftUI
import TestSupport
import Testing

@MainActor
@Suite(
  "File › Open Run…: a legacy run's layers in a sidebar, each shown in the viewer",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct LegacyRunWindowTests {
  /// A legacy run folder: rgb_base + syn_Ha + syn_OIII, 4×3, with run.json channels.
  static func run(in scratch: URL) throws -> URL {
    let run = scratch.appendingPathComponent("M_31/20261018_191749")
    try FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)
    let header = try FITSFile.parse(Data(("END" + String(repeating: " ", count: 2877)).utf8)).header
    for (name, planes) in [("rgb_base", 3), ("syn_Ha", 1), ("syn_OIII", 1)] {
      let image = AstroImage(
        width: 4, height: 3,
        planes: (0..<planes).map { plane in (0..<12).map { Float($0 + plane) / 20 } },
        metadata: ImageMetadata(header: header))
      try FITSFile.create(image, keeping: nil, at: run.appendingPathComponent(name + ".fits"))
    }
    let runJSON = #"""
      {"object": "M_31", "run_id": "20261018_191749", "channels": [
        {"filter": "RGB", "stacked_frames": 76}, {"filter": "RGB-dualband", "stacked_frames": 34}]}
      """#
    try Data(runJSON.utf8).write(to: run.appendingPathComponent("run.json"))
    return run
  }

  @Test(
    "the sidebar lists the layers with role, file, size and frames; a layer opens in the viewer",
    .scratchDirectory)
  func testLayersAndSelection() async throws {
    let folder = try Self.run(in: ScratchDirectory.url)
    let model = try await LegacyRunModel.open(folder: folder)
    #expect(model.title == "M_31 · 20261018_191749")
    #expect(model.rows.map(\.name) == ["RGB", "Ha", "OIII"])
    #expect(
      model.rows.map(\.detail) == [
        "rgb · rgb_base.fits · 4×3 · 76 frames", "line · syn_Ha.fits · 4×3 · 34 frames",
        "line · syn_OIII.fits · 4×3 · 34 frames",
      ])
    #expect(model.viewer == nil)
    try await model.select("Ha")
    let viewer = try #require(model.viewer)
    #expect(viewer.model.image.planes.count == 1 && viewer.model.image.width == 4)
    #expect(model.selected == "Ha")
  }

  @Test("opening records the run in the project as a read-only path, once", .scratchDirectory)
  func testOpenRecordsSource() async throws {
    let scratch = try ScratchDirectory.url
    let folder = try Self.run(in: scratch)
    let document = try ProjectDocument(type: ProjectPackage.typeIdentifier)
    defer { document.close() }
    let controller = try await LegacyRunWindow.open(folder, into: document)
    #expect(controller.window?.title == "M_31 · 20261018_191749")
    let second = try await LegacyRunWindow.open(folder, into: document)
    let sources = try #require(try document.projectSources())
    #expect(sources.map(\.path) == [folder.standardizedFileURL.path])
    #expect(sources.allSatisfy { $0.kind == .legacyRun && $0.readOnly })
    #expect(document.isDocumentEdited, "the project changed: it offers to be saved")
    controller.window?.close()
    second.window?.close()
  }

  @Test("the window's view lays out the sidebar and the selected layer's viewer", .scratchDirectory)
  func testViewLaysOut() async throws {
    let model = try await LegacyRunModel.open(folder: Self.run(in: ScratchDirectory.url))
    let empty = NSHostingView(rootView: LegacyRunView(model: model))
    empty.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
    empty.layoutSubtreeIfNeeded()
    try await model.select("RGB")
    let host = NSHostingView(rootView: LegacyRunView(model: model))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    #expect(model.selected == "RGB" && model.viewer != nil)
    #expect(host.fittingSize.width > 0)
  }

  @Test("-openRun at launch opens the run with its base layer shown", .scratchDirectory)
  func testLaunchArgumentOpensRun() async throws {
    let folder = try Self.run(in: ScratchDirectory.url)
    let suite = "fr.astrostack.tests.launch.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(folder.path, forKey: "openRun")
    await AppDelegate.openLaunchArguments(defaults)
    let window = try #require(
      LegacyRunWindow.openWindows.first { $0.model.source.folder.path == folder.path })
    #expect(window.model.selected == "RGB" && window.model.viewer != nil)
    window.window?.close()
  }

  @Test(
    "a layer that fails to load keeps the one shown, says why, and can be retried",
    .scratchDirectory)
  func testFailedLoadKeepsPreviousLayer() async throws {
    let folder = try Self.run(in: ScratchDirectory.url)
    let model = try await LegacyRunModel.open(folder: folder)
    try await model.select("RGB")
    try Data("broken".utf8).write(to: folder.appendingPathComponent("syn_Ha.fits"))
    await #expect(throws: (any Error).self) { try await model.select("Ha") }
    #expect(model.selected == "RGB" && model.viewer?.model.image.planes.count == 3)
    #expect(model.failure?.hasPrefix("syn_Ha.fits") == true)
    await #expect(throws: (any Error).self) { try await model.select("Ha") }
  }

  @Test("-openRun on a folder that is not a run reports the error", .scratchDirectory)
  func testLaunchArgumentReportsFailure() async throws {
    let suite = "fr.astrostack.tests.launch.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(try ScratchDirectory.url.path, forKey: "openRun")
    var reported = 0
    await AppDelegate.openLaunchArguments(defaults) { _ in reported += 1 }
    #expect(reported == 1)
  }

  @Test("the folder picker starts in the runs folder and picks folders only")
  func testRunPanel() {
    let panel = LegacyRunWindow.runPanel()
    #expect(panel.canChooseDirectories && !panel.canChooseFiles)
    #expect(panel.directoryURL?.path.hasSuffix("Documents/astro/runs") == true)
  }

  @Test("a failed open is reported, never swallowed", .scratchDirectory)
  func testFailureIsReported() async throws {
    let empty = try ScratchDirectory.url.appendingPathComponent("not-a-run")
    try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
    var reported: [any Error] = []
    let window = await LegacyRunWindow.open(empty, into: nil) { reported.append($0) }
    #expect(window == nil)
    #expect(reported.compactMap { $0 as? LegacyRunError } == [.notARun(empty.path)])
  }

  @Test("a folder that is not a run is an error, no window opens", .scratchDirectory)
  func testRefusesNonRun() async throws {
    let empty = try ScratchDirectory.url.appendingPathComponent("not-a-run")
    try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
    await #expect(throws: LegacyRunError.notARun(empty.path)) {
      _ = try await LegacyRunWindow.open(empty, into: nil)
    }
  }
}
