import ImageKit
import RenderKit
import Testing

@MainActor
@Suite("ViewerModel: the viewer's state, applied exactly as shown")
struct ViewerModelTests {
  static func model(width: Int = 40, height: Int = 20) throws -> ViewerModel {
    let header = try ViewerTests.header([("ROWORDER", "'TOP-DOWN'")])
    let plane = (0..<width * height).map { 0.1 + Float($0 % 7) / 1000 }
    let image = AstroImage(
      width: width, height: height, planes: [plane, plane, plane],
      metadata: ImageMetadata(header: header))
    return ViewerModel(image: image)
  }

  @Test("auto shows Siril's autostretch, manual starts from it and keeps edits, off shows none")
  func testStretchModes() throws {
    let model = try Self.model()
    let auto = AutoSTF.compute(planes: model.image.planes, linked: false)
    #expect(model.stretch == .auto)
    #expect(model.frame.stf == auto)

    model.stretch = .manual
    #expect(model.frame.stf == auto)
    model.manualSTF[1] = STFParameters(shadows: 0.05, midtone: 0.3, highlights: 0.9)
    #expect(model.frame.stf?[1] == STFParameters(shadows: 0.05, midtone: 0.3, highlights: 0.9))

    model.stretch = .off
    #expect(model.frame.stf == nil)
    model.stretch = .manual
    #expect(model.frame.stf?[1] == STFParameters(shadows: 0.05, midtone: 0.3, highlights: 0.9))

    model.linked = true
    model.stretch = .auto
    #expect(model.frame.stf == AutoSTF.compute(planes: model.image.planes, linked: true))
    // From Auto, Manual starts from the stretch on screen (here the linked one).
    model.stretch = .manual
    #expect(model.frame.stf == AutoSTF.compute(planes: model.image.planes, linked: true))
  }

  @Test("⌘0 fits the view, ⌘1 is 1:1 around the view centre")
  func testFitAndActualSize() throws {
    let model = try Self.model(width: 400, height: 200)
    model.viewSize = SIMD2(200, 200)
    model.zoomToFit()
    #expect(
      model.frame.transform
        == .fit(imageWidth: 400, imageHeight: 200, viewWidth: 200, viewHeight: 200))
    model.zoomToActualSize()
    #expect(model.frame.transform.scale == 1)
    #expect(model.frame.transform.imagePoint(viewX: 100, viewY: 100) == SIMD2(200, 100))
  }

  @Test("the region tool sets the histogram's region; the compare key and split set the frame")
  func testRegionAndCompare() throws {
    let model = try Self.model()
    model.frame.transform = ViewTransform(scale: 1, origin: .zero)
    model.drag(from: SIMD2(2, 3), to: SIMD2(12, 9), tool: .region)
    #expect(model.frame.region == PixelRegion(x: 2, y: 3, width: 10, height: 6))
    model.clearRegion()
    #expect(model.frame.region == nil)

    model.drag(from: SIMD2(5, 5), to: SIMD2(8, 1), tool: .pan)
    #expect(model.frame.transform.origin == SIMD2(-3, 4))

    model.drag(from: SIMD2(5, 5), to: SIMD2(17, 1), tool: .split)
    #expect(model.frame.compare == .split(atViewX: 17))
    model.compareKeyHeld = true
    #expect(model.frame.compare == .reference)
    model.compareKeyHeld = false
    #expect(model.frame.compare == .split(atViewX: 17))
  }

  @Test("a bottom-up image is shown flipped: readout and histogram region use stored rows")
  func testBottomUpCoordinates() throws {
    let header = try ViewerTests.header([("ROWORDER", "'BOTTOM-UP'")])
    let plane = (0..<12).map(Float.init)
    let model = ViewerModel(
      image: AstroImage(
        width: 3, height: 4, planes: [plane], metadata: ImageMetadata(header: header)))
    model.frame.transform = ViewTransform(scale: 1, origin: .zero)
    #expect(model.frame.flipRows)
    model.hover(atView: SIMD2(1.5, 0.5))
    #expect(model.readout?.y == 3 && model.readout?.values == [10])
    model.drag(from: SIMD2(0, 0), to: SIMD2(2, 1), tool: .region)
    #expect(model.frame.region == PixelRegion(x: 0, y: 0, width: 2, height: 1))
    #expect(
      model.frame.storedRegion(imageHeight: 4) == PixelRegion(x: 0, y: 3, width: 2, height: 1))
  }

  @Test("hovering reads the pixel under the cursor; outside the image reads nothing")
  func testHoverReadout() throws {
    let model = try Self.model()
    model.frame.transform = ViewTransform(scale: 2, origin: SIMD2(1, 0))
    model.hover(atView: SIMD2(3.5, 4.9))
    #expect(model.readout?.x == 8 && model.readout?.y == 9)
    #expect(
      model.readout?.values == [Float](repeating: model.image.planes[0][9 * 40 + 8], count: 3))
    model.hover(atView: SIMD2(-3, 0))
    #expect(model.readout == nil)
  }
}
