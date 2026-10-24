import AstroStackApp
import Foundation
import Metal
import ProcessKit
import RenderKit
import Testing

extension StudioWorkspaceModelTests {
  /// How the viewer stops showing a preview.
  enum PreviewEnd: String, CaseIterable, Sendable {
    case closePanel, previewFailure, historyMove
  }

  @Test(
    "the viewer's subject is the preview while one is shown, the image once the head is back",
    .scratchDirectory, arguments: PreviewEnd.allCases)
  func testStudio_viewerSubject_followsPreview(_ end: PreviewEnd) async throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.workspace(opened, bundle: StudioModelTests.bundle())
    let viewer = workspace.viewer.model
    #expect(viewer.subject == .image)

    workspace.choose(StretchProcess.id)
    await workspace.previewNow()
    #expect(workspace.isPreviewing && viewer.subject == .preview, "Stretch's defaults previewed")

    switch end {
    case .closePanel:
      workspace.closePanel()
    case .previewFailure:
      // No starless layer: the preview fails and the head is shown again.
      workspace.choose(StarRecompositionProcess.id)
      await workspace.previewNow()
      #expect(workspace.failure != nil)
    case .historyMove:
      try workspace.apply()
      #expect(workspace.studio.steps.last?.processID == StretchProcess.id)
    }
    #expect(!workspace.isPreviewing && viewer.subject == .image)
  }

  @Test(
    "on the head, the panel's input histogram and the viewer's linear one count the same bins",
    .scratchDirectory, .enabled(if: MTLCreateSystemDefaultDevice() != nil, "no Metal device"))
  func testStudio_panelAndViewerHistograms_agreeOnHead() throws {
    let opened = try StudioModelTests.project()
    defer { try? opened.package.close() }
    let workspace = try Self.workspace(opened, bundle: StudioModelTests.bundle())
    workspace.choose(CurvesProcess.id)
    let sample = try #require(workspace.panel?.sample)
    workspace.closePanel()

    // The viewer's whole-image linear histogram of the head, every pixel (its default stride 2
    // only thins the sample).
    var frame = workspace.viewer.model.frame
    (frame.region, frame.histogramDomain, frame.histogramStride) = (nil, .linear, 1)
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm, width: 16, height: 16, mipmapped: false)
    descriptor.usage = [.renderTarget, .shaderWrite, .shaderRead]
    let device = try #require(MTLCreateSystemDefaultDevice())
    let output = try #require(device.makeTexture(descriptor: descriptor))
    let viewer = try workspace.viewer.renderer.render(
      image: workspace.viewer.texture, reference: nil, frame: frame, into: output)

    #expect(viewer.count == sample.bins.count && sample.bins.count == 3)
    for (channel, (panel, shown)) in zip(sample.bins, viewer).enumerated() {
      let (panelTotal, shownTotal) = (Double(panel.reduce(0, +)), Double(shown.reduce(0, +)))
      let delta = zip(panel, shown).reduce(0.0) { sum, pair in
        sum + abs(Double(pair.0) / panelTotal - Double(pair.1) / shownTotal)
      }
      #expect(delta <= 0.01, "channel \(channel): Σ|Δ| of the normalised bins")
    }
  }
}
