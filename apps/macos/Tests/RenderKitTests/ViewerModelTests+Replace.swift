import ImageKit
import RenderKit
import Testing

/// Card 0087: the Studio's head changes under the viewer without rebuilding it — zoom, tool,
/// region and the stretch mode stay; the autostretch follows the new image, manual numbers stay.
@MainActor
@Suite("ViewerModel.replace — a new head under the same viewer")
struct ViewerModelReplaceTests {
  static func image(_ value: Float, planes: Int = 3) -> AstroImage {
    let plane = (0..<64).map { value + Float($0 % 9) / 100 }
    return AstroImage(
      width: 8, height: 8, planes: Array(repeating: plane, count: planes),
      metadata: ImageMetadata(rowOrder: .topDown))
  }

  @Test("replace keeps the view, follows auto, keeps manual numbers")
  func testReplaceKeepsTheView() {
    let model = ViewerModel(image: Self.image(0.1))
    model.frame.transform = ViewTransform(scale: 2, origin: SIMD2(3, 4))
    model.tool = .region
    let before = model.autoParameters

    model.replace(image: Self.image(0.4))
    #expect(model.image.planes[0][0] == 0.4)
    #expect(model.frame.transform == ViewTransform(scale: 2, origin: SIMD2(3, 4)))
    #expect(model.tool == .region && model.stretch == .auto)
    #expect(model.autoParameters != before, "auto follows the new image")
    #expect(model.frame.stf == model.autoParameters)

    model.stretch = .manual
    let manual = model.manualSTF
    model.replace(image: Self.image(0.7))
    #expect(model.stretch == .manual && model.manualSTF == manual && model.frame.stf == manual)
  }

  @Test("a head with another plane count gets its own stretch")
  func testReplaceChangesPlaneCount() {
    let model = ViewerModel(image: Self.image(0.1, planes: 1))
    model.stretch = .manual
    model.replace(image: Self.image(0.3, planes: 3))
    #expect(model.statistics.count == 3 && model.manualSTF.count == 3)
    #expect(model.frame.stf?.count == 3)
  }
}

extension ViewerModelReplaceTests {
  /// Card 0090: a region is in the pixels of the image it was drawn on; a head of another size
  /// (a crop, a quarter turn) drops it rather than count pixels that are not there.
  @Test("a head of the same size keeps the region, another size drops it")
  func testReplaceDropsRegionOnResize() {
    let model = ViewerModel(image: Self.image(0.1))
    model.frame.transform = ViewTransform(scale: 1, origin: .zero)
    model.drag(from: [1, 1], to: [5, 5], tool: .region)
    model.replace(image: Self.image(0.2))
    #expect(model.frame.region == PixelRegion(x: 1, y: 1, width: 4, height: 4))
    model.replace(
      image: AstroImage(
        width: 4, height: 8, planes: [[Float](repeating: 0.1, count: 32)],
        metadata: ImageMetadata(rowOrder: .topDown)))
    #expect(model.frame.region == nil)
  }
}
