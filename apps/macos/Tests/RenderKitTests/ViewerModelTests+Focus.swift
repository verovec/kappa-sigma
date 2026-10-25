import Foundation
import ImageKit
import RenderKit
import Testing

extension ViewerModelTests {
  @Test(
    "zoom in/out by 2 around the centre, clamped to ViewTransform.scales",
    arguments: [
      (1.0, 0.5, 2.0), (1.0 / 64, 1.0 / 64, 1.0 / 32), (64.0, 32.0, 64.0), (2.0, 1.0, 4.0),
    ])
  func testZoomInOut(scale: Double, zoomedIn: Double, zoomedOut: Double) throws {
    let (model, cleanUp) = try Self.panelModel(width: 400, height: 200)
    defer { cleanUp() }
    model.viewSize = SIMD2(200, 100)
    let start = ViewTransform(scale: scale, origin: SIMD2(10, -4))
    let centre = start.imagePoint(viewX: 100, viewY: 50)

    model.frame.transform = start
    model.zoomIn()
    #expect(model.frame.transform.scale == zoomedIn)
    #expect(model.frame.transform.imagePoint(viewX: 100, viewY: 50) == centre)

    model.frame.transform = start
    model.zoomOut()
    #expect(model.frame.transform.scale == zoomedOut)
    #expect(model.frame.transform.imagePoint(viewX: 100, viewY: 50) == centre)
  }

  @Test(
    "focus hides the panel without remembering it, exit puts back the panel as it was",
    arguments: [true, false])
  func testFocus_RestoresPanel(shown: Bool) throws {
    let (defaults, name) = try ViewerPanelSettingTests.suite()
    defer { defaults.removePersistentDomain(forName: name) }
    let setting = ViewerPanelSetting(defaults: defaults)
    setting.showsPanel = shown
    let model = ViewerModel(image: try Self.model().image, panelSetting: setting)
    model.stretch = .manual
    let before = model.frame.stf

    model.isFocused = true
    #expect(!model.showsPanel)
    #expect(setting.showsPanel == shown, "focus is not the user's panel choice")
    model.isFocused = false
    #expect(model.showsPanel == shown)
    #expect(setting.showsPanel == shown)
    #expect(model.frame.stf == before, "display only: the stretch is untouched")
  }

  @Test("focused, the image fills each new view size until the user zooms; then it is kept")
  func testFocus_FitsUntilZoomed() throws {
    let (model, cleanUp) = try Self.panelModel(width: 400, height: 200)
    defer { cleanUp() }
    model.viewSize = SIMD2(200, 200)
    model.frame.transform = ViewTransform(scale: 1, origin: SIMD2(50, 0))

    model.isFocused = true
    #expect(
      model.frame.transform
        == .fit(imageWidth: 400, imageHeight: 200, viewWidth: 200, viewHeight: 200))
    model.resizeView(to: SIMD2(800, 400))
    #expect(
      model.frame.transform
        == .fit(imageWidth: 400, imageHeight: 200, viewWidth: 800, viewHeight: 400))

    model.zoomIn()
    let zoomed = model.frame.transform
    model.resizeView(to: SIMD2(1600, 800))
    #expect(model.frame.transform.scale == zoomed.scale, "the user's zoom is never reset")

    model.isFocused = false
    let kept = model.frame.transform
    model.resizeView(to: SIMD2(1600, 800))
    #expect(model.frame.transform == kept, "exit keeps the transform")
  }

  @Test("pointer moves are counted for the HUD only while focused")
  func testPointerMoves_OnlyFocused() throws {
    let (model, cleanUp) = try Self.panelModel()
    defer { cleanUp() }
    model.hover(atView: SIMD2(1, 1))
    #expect(model.pointerMoves == 0)
    model.isFocused = true
    model.hover(atView: SIMD2(2, 1))
    #expect(model.pointerMoves == 1)
  }
}
