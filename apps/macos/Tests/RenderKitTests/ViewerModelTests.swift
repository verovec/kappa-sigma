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

  @Test(
    "a handle drag in Auto goes Manual from the auto values, moves one parameter; Reset → Auto"
  )
  func testHandleDragEditsManualSTF() throws {
    let model = try Self.model()
    let auto = model.autoParameters
    #expect(model.stretch == .auto)

    // Linear domain: the midtone handle lands on the linear value it is dropped at.
    model.dragHandle(.midtone, channel: 1, to: 0.3)
    #expect(model.stretch == .manual)
    #expect(model.manualSTF[0] == auto[0] && model.manualSTF[2] == auto[2])
    let edited = model.manualSTF[1]
    #expect(edited.shadows == auto[1].shadows && edited.highlights == auto[1].highlights)
    #expect(abs(edited.midtoneValue - 0.3) < 1e-12)
    #expect(model.frame.stf == model.manualSTF, "the frame shows the manual numbers")
    model.endHandleDrag()

    // Display domain: the pixel value shown at the drop position becomes the new black point.
    model.frame.histogramDomain = .display
    let before = model.manualSTF[1]
    model.dragHandle(.shadows, channel: 1, to: 0.2)
    let after = model.manualSTF[1]
    #expect(abs(after.shadows - before.linearValue(atPosition: 0.2, in: .display)) < 1e-12)
    #expect(after.midtone == before.midtone && after.highlights == before.highlights)

    // Every event of one drag maps from the stretch at press time: dropping twice at the same
    // position gives the same stretch, it never compounds; the next drag starts from the result.
    let once = model.manualSTF[1]
    model.dragHandle(.shadows, channel: 1, to: 0.2)
    #expect(model.manualSTF[1] == once)
    model.endHandleDrag()
    model.dragHandle(.shadows, channel: 1, to: 0.2)
    #expect(model.manualSTF[1].shadows > once.shadows)
    model.endHandleDrag()

    model.resetToAuto()
    #expect(model.stretch == .auto)
    #expect(model.frame.stf == auto)

    // Off has no handles to drag: nothing changes.
    model.stretch = .off
    model.dragHandle(.highlights, channel: 0, to: 0.5)
    #expect(model.stretch == .off && model.frame.stf == nil)
  }

  @Test("the statistics behind the controls are measured once and follow the linked toggle")
  func testStatisticsFollowLinking() throws {
    let model = try Self.model()
    let measured = STFMapping.measure(planes: model.image.planes, linked: false)
    #expect(model.statistics == measured)
    #expect(model.mapping(for: 1) == measured[1])
    #expect(
      model.mapping(for: 1).parameters(sigma: -2.8, targetBackground: 0.25)
        == model.autoParameters[1])
    model.linked = true
    let linked = STFMapping.measure(planes: model.image.planes, linked: true)
    #expect(model.mapping(for: 2) == linked[2])
    #expect(model.autoParameters == AutoSTF.compute(planes: model.image.planes, linked: true))
    // A model built from precomputed statistics (the app measures off the main actor) is the same.
    let precomputed = ViewerModel(image: model.image, statistics: measured)
    #expect(
      precomputed.autoParameters == AutoSTF.compute(planes: model.image.planes, linked: false))
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
