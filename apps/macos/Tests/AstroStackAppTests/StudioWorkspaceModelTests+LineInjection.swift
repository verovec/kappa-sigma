import AstroStackApp
import Foundation
import ImageKit
import Metal
import ProcessKit
import Testing

extension StudioWorkspaceModelTests {
  /// The test bundle with a constant Hα layer of 0.5.
  static func bundleWithHa() -> PipelineBundle {
    let base = StudioModelTests.bundle()
    let rgb = base.layers["RGB"]
    let width = rgb?.width ?? 0
    let height = rgb?.height ?? 0
    let ha = AstroImage(
      width: width, height: height, planes: [[Float](repeating: 0.5, count: width * height)],
      metadata: ImageMetadata(rowOrder: .topDown))
    var layers = base.layers
    layers["Ha"] = ha
    var layerStats = base.layerStats
    layerStats["Ha"] = StudioSession.stats(of: ha)
    return PipelineBundle(stats: base.stats, layers: layers, layerStats: layerStats)
  }

  @Test(
    "the line injection panel shows its preview's maximum per channel, no other panel (card 0120)",
    .scratchDirectory, .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
  func testLineInjection_ShowsPreviewMaximum() async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.workspace(opened, bundle: Self.bundleWithHa())
    let head = workspace.studio.head.planes.map { Double($0.max() ?? 0) }
    workspace.choose(LineInjectionProcess.id)
    await workspace.settlePreview()
    let panel = try #require(workspace.panel)
    #expect(panel.shownMaxima == head, "gains 0: the preview is the head")

    panel.set("haGain", .number(2))
    await workspace.settlePreview()
    #expect(panel.shownMaxima.count == 3)
    #expect(abs((panel.shownMaxima.first ?? 0) - (head[0] + 1)) <= 1e-6, "red + 2 × 0.5")
    #expect(Array(panel.shownMaxima.dropFirst()) == Array(head.dropFirst()))

    try workspace.apply()
    let applied = workspace.studio.head.planes.map { Double($0.max() ?? 0) }
    #expect(abs(applied[0] - (head[0] + 1)) <= 1e-6)
    #expect(panel.shownMaxima == applied, "the head on screen now, with its range above the old")

    workspace.choose(ColourBalanceProcess.id)
    await workspace.settlePreview()
    #expect(try #require(workspace.panel).shownMaxima.isEmpty)
  }

  @Test(
    "the shown maximum skips a NaN pixel",
    arguments: [
      ([0.2, .nan, 1.75, 0.4], 1.75), ([.nan, .nan], -Double.infinity), ([0.5, 0.25], 0.5),
    ] as [([Float], Double)])
  func testFiniteMaximum(plane: [Float], expected: Double) {
    #expect(StudioWorkspaceModel.finiteMaximum(plane) == expected)
  }
}
