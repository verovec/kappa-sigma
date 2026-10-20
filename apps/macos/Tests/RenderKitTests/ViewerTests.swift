import Foundation
import ImageKit
import RenderKit
import Testing

@Suite("Viewer: view ↔ image mapping, region, pixel readout")
struct ViewerTests {
  static let size = (width: 400.0, height: 300.0)

  @Test("fit shows the whole image centred; 1:1 keeps the point under the view centre")
  func testFitAndOneToOne() {
    let fit = ViewTransform.fit(
      imageWidth: 6000, imageHeight: 4000, viewWidth: 600, viewHeight: 600)
    #expect(fit.scale == 10)
    #expect(fit.imagePoint(viewX: 0, viewY: 0) == SIMD2(0, -1000))
    #expect(fit.imagePoint(viewX: 300, viewY: 300) == SIMD2(3000, 2000))

    let one = fit.oneToOne(viewWidth: 600, viewHeight: 600)
    #expect(one.scale == 1)
    #expect(one.imagePoint(viewX: 300, viewY: 300) == SIMD2(3000, 2000))
  }

  @Test(
    "zoom keeps the image point under the cursor; pan moves it with the drag",
    arguments: [0.5, 2, 1.25])
  func testZoomAroundCursorAndPan(factor: Double) {
    let start = ViewTransform(scale: 4, origin: SIMD2(100, 50))
    let cursor = SIMD2(123.0, 77.0)
    let before = start.imagePoint(viewX: cursor.x, viewY: cursor.y)
    let zoomed = start.zoomed(by: factor, aroundViewX: cursor.x, viewY: cursor.y)
    #expect(zoomed.scale == 4 / factor)
    let after = zoomed.imagePoint(viewX: cursor.x, viewY: cursor.y)
    #expect(abs(after.x - before.x) < 1e-9 && abs(after.y - before.y) < 1e-9)

    let panned = zoomed.panned(byViewX: 10, viewY: -4)
    let moved = panned.imagePoint(viewX: cursor.x + 10, viewY: cursor.y - 4)
    #expect(abs(moved.x - after.x) < 1e-9 && abs(moved.y - after.y) < 1e-9)
  }

  @Test("zoom is bounded: 1/64 to 64 image pixels per view pixel")
  func testZoomBounds() {
    let start = ViewTransform(scale: 1, origin: .zero)
    #expect(start.zoomed(by: 1e6, aroundViewX: 0, viewY: 0).scale == 1.0 / 64)
    #expect(start.zoomed(by: 1e-6, aroundViewX: 0, viewY: 0).scale == 64)
  }

  @Test("a dragged region is the image-pixel rectangle under it, clipped to the image")
  func testRegionFromDrag() throws {
    let view = ViewTransform(scale: 2, origin: SIMD2(-10, 4))
    let region = try #require(
      view.region(fromViewX: 30, viewY: 20, toViewX: 2, viewY: 60, imageWidth: 100, imageHeight: 80)
    )
    #expect(region == PixelRegion(x: 0, y: 44, width: 50, height: 36))
    #expect(
      view.region(
        fromViewX: -50, viewY: 0, toViewX: -40, viewY: 9, imageWidth: 100, imageHeight: 80) == nil)
  }

  @Test(
    "readout returns the exact plane values; RA/Dec within 1″ of the oracle with WCS, nil without")
  func testPixelReadoutAndWCS() throws {
    let planes: [[Float]] = [
      [0.1, 0.2, 0.3, 0.4, 0.5, 0.6], [1, 2, 3, 4, 5, 6], [-1, -2, -3, -4, -5, -6],
    ]
    let solved = ImageMetadata(
      header: try Self.header([
        ("CTYPE1", "'RA---TAN'"), ("CTYPE2", "'DEC--TAN'"), ("CRPIX1", "2"), ("CRPIX2", "1"),
        ("CRVAL1", "83.82"), ("CRVAL2", "-5.39"), ("CD1_1", "-1.0E-03"), ("CD1_2", "0"),
        ("CD2_1", "0"), ("CD2_2", "1.0E-03"),
      ]))
    let image = AstroImage(width: 3, height: 2, planes: planes, metadata: solved)

    let readout = try #require(PixelReadout(image: image, x: 2, y: 1))
    #expect(readout.values == [0.6, 6, -6])
    let sky = try #require(readout.sky)
    // Oracle: ξ = −1e-3 · (3 − 2) deg, η = 1e-3 · (2 − 1) deg around (83.82, −5.39), small-angle
    // tangent plane (error ≪ 1″ at 3.6″ offsets).
    let dec = -5.39 + 1.0E-03
    let ra = 83.82 - 1.0E-03 / cos(dec * .pi / 180)
    #expect(abs(sky.dec - dec) * 3600 <= 1)
    #expect(abs(sky.ra - ra) * cos(dec * .pi / 180) * 3600 <= 1)

    var unsolved = image.metadata
    unsolved.wcs = nil
    let plain = AstroImage(width: 3, height: 2, planes: planes, metadata: unsolved)
    #expect(try #require(PixelReadout(image: plain, x: 0, y: 0)).sky == nil)
    #expect(PixelReadout(image: plain, x: 3, y: 0) == nil)
    #expect(PixelReadout(image: plain, x: 0, y: -1) == nil)
  }

  static func header(_ pairs: [(String, String)]) throws -> FITSHeader {
    func card(_ key: String, _ value: String) -> String {
      (key.padding(toLength: 8, withPad: " ", startingAt: 0) + "= " + value)
        .padding(toLength: 80, withPad: " ", startingAt: 0)
    }
    var text = pairs.map { card($0.0, $0.1) }.joined() + "END"
    while text.utf8.count % 2880 != 0 { text += " " }
    return try FITSFile.parse(Data(text.utf8)).header
  }
}

@Suite("Readout text: RA in hours, Dec in degrees, sexagesimal")
struct SkyTextTests {
  @Test(
    "RA hh:mm:ss.s and Dec ±dd:mm:ss, carried at the rounding edge",
    arguments: [
      (10.684708, 41.268611, "00h42m44.3s", "+41°16′07″"),
      (83.822083, -5.391111, "05h35m17.3s", "−05°23′28″"),
      (359.99999, -0.0000001, "00h00m00.0s", "−00°00′00″"),
      (0, 89.9999999, "00h00m00.0s", "+90°00′00″"),
    ])
  func testSexagesimal(ra: Double, dec: Double, raText: String, decText: String) {
    let sky = PixelReadout.Sky(ra: ra, dec: dec)
    #expect(sky.raText == raText)
    #expect(sky.decText == decText)
  }
}
