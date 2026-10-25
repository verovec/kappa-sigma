import Foundation
import ImageKit
import RenderKit
import Testing

extension ViewerModelTests {
  /// A model whose panel choice lives in a scratch suite, emptied first.
  static func panelModel(width: Int = 40, height: Int = 20) throws -> (ViewerModel, () -> Void) {
    let (defaults, name) = try ViewerPanelSettingTests.suite()
    let header = try ViewerTests.header([("ROWORDER", "'TOP-DOWN'")])
    let plane = (0..<width * height).map { 0.1 + Float($0 % 7) / 1000 }
    let image = AstroImage(
      width: width, height: height, planes: [plane, plane, plane],
      metadata: ImageMetadata(header: header))
    let model = ViewerModel(image: image, panelSetting: ViewerPanelSetting(defaults: defaults))
    return (model, { defaults.removePersistentDomain(forName: name) })
  }

  @Test("hiding the panel changes no display value (R2: it hides controls, never a value)")
  func testHidingPanel_KeepsFrame() throws {
    let (model, cleanUp) = try Self.panelModel()
    defer { cleanUp() }
    model.stretch = .manual
    model.manualSTF[0] = STFParameters(shadows: 0.02, midtone: 0.4, highlights: 0.95)
    model.frame.clippingOverlay = true
    model.frame.region = PixelRegion(x: 1, y: 2, width: 5, height: 4)
    model.frame.transform = ViewTransform(scale: 0.5, origin: SIMD2(3, -1))
    model.drag(from: .zero, to: SIMD2(12, 0), tool: .split)
    let before = model.frame

    model.showsPanel = false
    #expect(model.frame == before)
    model.showsPanel = true
    #expect(model.frame == before)
  }

  @Test(
    "a wider or narrower view keeps the image point under its centre and the zoom",
    arguments: [SIMD2<Double>(300, 100), SIMD2<Double>(150, 100)])
  func testResize_KeepsCentre(size: SIMD2<Double>) throws {
    let (model, cleanUp) = try Self.panelModel(width: 400, height: 200)
    defer { cleanUp() }
    model.viewSize = SIMD2(200, 100)
    model.frame.transform = ViewTransform(scale: 0.5, origin: SIMD2(150, 70))
    let centre = model.frame.transform.imagePoint(viewX: 100, viewY: 50)

    model.resizeView(to: size)
    #expect(model.viewSize == size)
    #expect(model.frame.transform.scale == 0.5, "the zoom level is never reset")
    #expect(model.frame.transform.imagePoint(viewX: size.x / 2, viewY: size.y / 2) == centre)
  }

  @Test(
    "a fitted image stays whole when the view grows, whatever the rounding of its scale",
    arguments: zip([5349, 6248, 4144], [1234, 1717, 997]))
  func testResize_FittedStaysWhole(imageWidth: Int, viewWidth: Int) throws {
    let (model, cleanUp) = try Self.panelModel(width: imageWidth, height: 10)
    defer { cleanUp() }
    model.viewSize = SIMD2(Double(viewWidth), 400)
    model.zoomToFit()
    let fitted = model.frame.transform.scale
    model.resizeView(to: SIMD2(Double(viewWidth) - 1, 400))
    #expect(model.frame.transform.scale > fitted, "a pixel narrower: fitted again, not cut")
  }

  @Test("a fitted image is fitted again only when it no longer fits")
  func testResize_RefitsOnlyWhenCut() throws {
    let (model, cleanUp) = try Self.panelModel(width: 400, height: 200)
    defer { cleanUp() }
    model.viewSize = SIMD2(200, 200)
    model.zoomToFit()
    model.resizeView(to: SIMD2(300, 200))
    #expect(model.frame.transform.scale == 2, "still whole: the zoom stays")

    model.resizeView(to: SIMD2(100, 200))
    #expect(
      model.frame.transform
        == .fit(imageWidth: 400, imageHeight: 200, viewWidth: 100, viewHeight: 200))
  }
}
