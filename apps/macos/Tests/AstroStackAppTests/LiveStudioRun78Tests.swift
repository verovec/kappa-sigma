import AppKit
import AstroStackApp
import Foundation
import ImageKit
import Metal
import ProcessKit
import ProjectKit
import SwiftUI
import TestSupport
import Testing

/// Card 0087's manual walk on run #78 (its recorded 1024 × 768 crop: RGB base, Hα, [OIII]):
/// combination (natural) → stretch (GHS) → curves → compare step 1 with the head → undo twice,
/// the Studio rendered in French and English at each stage (PNG attachments, the PR's
/// screenshots). Skips without the finish fixtures.
@MainActor
@Suite(
  "Live Studio on run #78's crop — combination, GHS, curves, compare, undo", .finishOracle,
  .tags(.live), .serialized, .timeLimit(.minutes(5)),
  .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
struct LiveStudioRun78Tests {
  static func bundle(_ root: URL) throws -> PipelineBundle {
    var layers: [String: AstroImage] = [:]
    for (id, file) in [("RGB", "rgb_base"), ("Ha", "syn_Ha"), ("OIII", "syn_OIII")] {
      layers[id] = try FITSFile.read(at: root.appendingPathComponent("crop/\(file).fits")).image()
    }
    let stats = layers.mapValues(StudioSession.stats(of:))
    let base = try #require(stats["RGB"])
    return PipelineBundle(stats: base, layers: layers, layerStats: stats)
  }

  static func render(_ workspace: StudioWorkspaceModel, _ name: String) throws {
    for language in ["fr", "en"] {
      let host = NSHostingView(
        rootView: StudioWorkspaceView(model: workspace)
          .environment(\.locale, Locale(identifier: language))
          .frame(width: 1400, height: 800)
          .background(Color(nsColor: .windowBackgroundColor)))
      host.appearance = NSAppearance(named: .darkAqua)
      host.frame = NSRect(x: 0, y: 0, width: 1400, height: 800)
      host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.2))
      let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      let png = try #require(bitmap.representation(using: .png, properties: [:]))
      Attachment.record(png, named: "studio-run78-\(name)-\(language).png")
    }
  }

  @Test("the walk: combination, GHS, curves, compare, undo twice", .scratchDirectory)
  func testWalk() async throws {
    let root = try #require(FinishOracle.root)
    let manifest = try FinishOracle.manifest()
    try #require(FinishOracle.verify(manifest.layers, root: root) == [])
    let package = try ProjectPackage.create(
      at: ScratchDirectory.url.appendingPathComponent("M31.astrostack"))
    defer { try? package.close() }
    let stack = try package.store.addStack(
      bundlePath: "stacks/78", sourceIDs: [], paramsJSON: "{}", imageRoles: ["RGB", "Ha", "OIII"])
    let studio = try StudioModel(
      store: package.store, stackID: stack.id,
      stackFolder: package.url.appendingPathComponent("stacks/78"), bundle: Self.bundle(root))
    let workspace = try StudioWorkspaceModel(studio: studio, base: [.color, .emission])
    try Self.render(workspace, "1-combination")

    workspace.choose(StretchProcess.id)
    let stretch = try #require(workspace.panel)
    stretch.set("mode", .choice("ghs"))
    stretch.set("ghsStretch", .number(4))
    stretch.set("ghsSymmetry", .number(0.02))
    await workspace.previewNow()
    try Self.render(workspace, "2-ghs-preview")
    try workspace.apply()

    workspace.choose(CurvesProcess.id)
    let curves = try #require(workspace.panel)
    curves.set("rgb", .points([CurvePoint(0, 0), CurvePoint(0.5, 0.6), CurvePoint(1, 1)]))
    try workspace.apply()
    #expect(studio.steps.map(\.processID) == ["channel-combination", "stretch", "curves"])
    try workspace.compare(toStep: 0)
    try Self.render(workspace, "3-curves-compare-step1")

    try workspace.compare(toStep: nil)
    try workspace.undo()
    try workspace.undo()
    #expect(studio.steps.map(\.processID) == ["channel-combination"])
    #expect(studio.canRedo)
    try Self.render(workspace, "4-undone-twice")
  }
}
