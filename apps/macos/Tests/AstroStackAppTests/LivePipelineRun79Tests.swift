import AppKit
import AstroStackApp
import Foundation
import ImageKit
import Metal
import ProcessKit
import ProjectKit
import StackKit
import SwiftUI
import TestSupport
import Testing

/// Run #79 (`IC_1848/20261018_221220`, the IC 1848 dual-band reference), when present.
enum RunSeventyNine {
  static var folder: URL? {
    let home = ProcessInfo.processInfo.environment["HOME"].map { URL(fileURLWithPath: $0) }
    let run = (home ?? FileManager.default.homeDirectoryForCurrentUser)
      .appendingPathComponent("Documents/astro/runs/IC_1848/20261018_221220")
    return FileManager.default.fileExists(atPath: run.appendingPathComponent("run.json").path)
      ? run : nil
  }
}

/// Card 0088's manual walk: run #79 in the Studio with the IC 1848 profile's pipeline — Run
/// halts at the emission screens, the Hα black point is lowered, Continue finishes, the result
/// is compared with the profile's pipeline saved first. The Studio is rendered in French and
/// English at each stage (PNG attachments, the PR's screenshots).
@MainActor
@Suite(
  "Live pipeline on run #79 — IC 1848 profile, stop at the screens, Continue, compare",
  .liveFixtures, .tags(.live), .serialized, .timeLimit(.minutes(10)),
  .enabled(if: RunSeventyNine.folder != nil, "run #79 absent"),
  .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
struct LivePipelineRun79Tests {
  static func render(_ view: some View, _ name: String) throws {
    for language in ["fr", "en"] {
      let host = NSHostingView(
        rootView: view.environment(\.locale, Locale(identifier: language))
          .frame(width: 1400, height: 800)
          .background(Color(nsColor: .windowBackgroundColor)))
      host.appearance = NSAppearance(named: .darkAqua)
      host.frame = NSRect(x: 0, y: 0, width: 1400, height: 800)
      host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.2))
      let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      let png = try #require(bitmap.representation(using: .png, properties: [:]))
      Attachment.record(png, named: "pipeline-run79-\(name)-\(language).png")
    }
  }

  @Test("IC 1848 profile: stop at the screens, adjust, Continue, compare", .scratchDirectory)
  func testWalk() async throws {
    let source = try LegacyRunSource(folder: try #require(RunSeventyNine.folder))
    let (bundle, roles, header) = try await StudioBundle.load(source)
    let registry = try ProcessRegistry.standard()
    let profile = try #require(
      try ProfileLibrary.builtins(registry: registry).first { $0.id == "emission-osc-dualband" })
    let combination = ParamSet.loading(
      profile.pipeline.steps[0].recipe.params, onto: ChannelCombinationProcess.schema
    ).params

    let package = try ProjectPackage.create(
      at: ScratchDirectory.url.appendingPathComponent("IC1848.astrostack"))
    defer { try? package.close() }
    let stack = try package.store.addStack(
      bundlePath: "stacks/79", sourceIDs: [], paramsJSON: "{}", imageRoles: ["RGB", "Ha", "OIII"])
    let studio = try StudioModel(
      store: package.store, stackID: stack.id, packageFolder: package.url,
      stackFolder: package.url.appendingPathComponent("stacks/79"), bundle: bundle,
      header: header, combination: combination)
    let workspace = try StudioWorkspaceModel(studio: studio, base: roles)
    let sidebar = try PipelineSidebarModel(
      workspace: workspace, pipeline: profile.pipeline, store: package.store, base: roles)
    workspace.pipeline = sidebar
    sidebar.save(as: "IC 1848 doux")

    await sidebar.run()
    #expect(sidebar.failure == nil)
    #expect(sidebar.stoppedAt == 2 && workspace.panel?.type.id == EmissionScreensProcess.id)
    let panel = try #require(workspace.panel)
    #expect(panel.params.number("haBlack") == 0.126, "the profile's value is in the panel")
    try Self.render(StudioWorkspaceView(model: workspace), "1-stopped-at-screens")

    panel.set("haBlack", .number(0.1))
    await sidebar.continueRun()
    #expect(sidebar.failure == nil && sidebar.stoppedAt == nil)
    #expect(
      studio.steps.map(\.processID)
        == ["channel-combination", "stretch", "emission-screens", "saturation"])
    try Self.render(StudioWorkspaceView(model: workspace), "2-continued")

    let differences = try sidebar.differences(from: "IC 1848 doux")
    #expect(
      differences == [
        PipelineDiff.Entry(
          step: 2, processID: "emission-screens",
          change: .param("haBlack", .number(0.126), .number(0.1)))
      ])
    try Self.render(
      PipelineDiffSheet(model: sidebar, savedName: "IC 1848 doux") {}, "3-compare")
  }
}
