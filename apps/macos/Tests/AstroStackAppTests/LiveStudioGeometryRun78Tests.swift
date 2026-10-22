import AstroStackApp
import Foundation
import ImageKit
import Metal
import ProcessKit
import ProjectKit
import RenderKit
import TestSupport
import Testing

/// Card 0090's manual walk on run #78's crop: a region on the galaxy → « Use region » → Apply →
/// emission screens. The screens read the moved Hα and [OIII]: away from the crop edge (the
/// star-removal radius reaches 4 px past it), the result equals the screens of the uncropped
/// head with the same statistics, then cropped — the layers stayed aligned. Screenshots in
/// French and English are attached. Skips without the finish fixtures.
@MainActor
@Suite(
  "Live geometry on run #78's crop — Use region, Apply, screens aligned", .finishOracle,
  .tags(.live), .serialized, .timeLimit(.minutes(5)),
  .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
struct LiveStudioGeometryRun78Tests {
  @Test("a crop from the region keeps the emission screens aligned", .scratchDirectory)
  func testCropKeepsScreensAligned() async throws {
    let root = try #require(FinishOracle.root)
    try #require(FinishOracle.verify(FinishOracle.manifest().layers, root: root) == [])
    let package = try ProjectPackage.create(
      at: ScratchDirectory.url.appendingPathComponent("M31.astrostack"))
    defer { try? package.close() }
    let stack = try package.store.addStack(
      bundlePath: "stacks/78", sourceIDs: [], paramsJSON: "{}", imageRoles: ["RGB", "Ha", "OIII"])
    let bundle = try LiveStudioRun78Tests.bundle(root)
    let studio = try StudioModel(
      store: package.store, stackID: stack.id, packageFolder: package.url,
      stackFolder: package.url.appendingPathComponent("stacks/78"), bundle: bundle)
    let workspace = try StudioWorkspaceModel(studio: studio, base: [.color, .emission])
    let before = studio.head

    workspace.choose(GeometryProcess.id)
    await workspace.previewNow()
    workspace.viewer.model.frame.transform = ViewTransform(scale: 1, origin: [0, 0])
    workspace.viewer.model.drag(from: [256, 160], to: [768, 608], tool: .region)
    try LiveStudioRun78Tests.render(workspace, "geometry-1-region")
    workspace.useRegion()
    await workspace.previewNow()
    try LiveStudioRun78Tests.render(workspace, "geometry-2-use-region")
    let geometry = try #require(workspace.panel).params
    try workspace.apply()
    #expect(studio.head.width == 512 && studio.head.height == 448)

    let session = studio.session
    let (stats, layerStats) = (session.stepStats, try session.layerStats())
    workspace.choose(EmissionScreensProcess.id)
    let screens = try #require(workspace.panel).params
    await workspace.previewNow()
    try workspace.apply()
    try LiveStudioRun78Tests.render(workspace, "geometry-3-screens")
    #expect(
      studio.steps.map(\.processID) == ["channel-combination", "geometry", "emission-screens"])

    // The reference: screens on the uncropped head and layers, the same statistics, then cropped.
    let device = session.device
    let runner = try ProcessRunner(device: device)
    let screened = try runner.run(
      EmissionScreensProcess(params: screens, device: device),
      input: GPUImage(device: device, image: before), stats: stats,
      layers: bundle.layers.mapValues { try GPUImage(device: device, image: $0) },
      layerStats: layerStats)
    let reference = try runner.run(
      GeometryProcess(params: geometry, device: device), input: screened,
      stats: LayerStats(channels: []), rowsBottomUp: before.metadata.rowOrder == .bottomUp
    ).read()
    let worst = Self.worstInterior(studio.head.planes, reference, width: 512, height: 448)
    #expect(worst <= 1e-5, "max |Δ| inside the margin: \(worst)")
  }

  /// The largest |Δ| more than 16 px from every edge (the star-removal radius reaches 4 px past
  /// the crop edge).
  static func worstInterior(_ got: [[Float]], _ want: [[Float]], width: Int, height: Int) -> Float {
    let margin = 16
    var worst: Float = 0
    for (lhs, rhs) in zip(got, want) {
      for y in margin..<(height - margin) {
        for x in margin..<(width - margin) {
          worst = max(worst, abs(lhs[y * width + x] - rhs[y * width + x]))
        }
      }
    }
    return worst
  }
}
