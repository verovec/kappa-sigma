import AppKit
import ImageKit
import RenderKit
import SwiftUI
import Testing

/// The SwiftUI layer laid out in an offscreen window for every panel state, and the histogram
/// plot rendered to pixels.
@MainActor
@Suite("ViewerView: the panel in every state, the histogram plot", .enabled(if: GPU.available))
struct ViewerViewTests {
  static func hosted(_ model: ViewerModel) throws -> NSHostingView<ViewerView> {
    let device = try GPU.requireDevice()
    let image = model.image
    let view = ViewerView(
      model: model, renderer: try ViewerRenderer(device: device),
      texture: try ImageTexture(
        device: device, width: image.width, height: image.height, planes: image.planes),
      reference: nil)
    let host = NSHostingView(rootView: view)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    return host
  }

  static func model(planes count: Int) throws -> ViewerModel {
    let header = try ViewerTests.header([
      ("ROWORDER", "'TOP-DOWN'"), ("CTYPE1", "'RA---TAN'"), ("CTYPE2", "'DEC--TAN'"),
      ("CRPIX1", "4"), ("CRPIX2", "4"), ("CRVAL1", "10.68"), ("CRVAL2", "41.27"),
      ("CD1_1", "-1.0E-03"), ("CD2_2", "1.0E-03"),
    ])
    let plane = (0..<64).map { 0.1 + Float($0 % 9) / 100 }
    return ViewerModel(
      image: AstroImage(
        width: 8, height: 8, planes: Array(repeating: plane, count: count),
        metadata: ImageMetadata(header: header)))
  }

  @Test(
    "every panel state lays out: stretch modes, region, readout with RA/Dec, histogram",
    arguments: [1, 3])
  func testPanelStates(planes: Int) throws {
    let model = try Self.model(planes: planes)
    let host = try Self.hosted(model)
    let empty = host.fittingSize

    model.histogram = Array(repeating: (0..<256).map { $0 % 7 }, count: planes)
    model.frame.region = PixelRegion(x: 1, y: 1, width: 4, height: 4)
    model.frame.transform = ViewTransform(scale: 0.5, origin: SIMD2(-2, -2))
    model.hover(atView: SIMD2(5, 5))
    #expect(model.readout?.sky != nil)
    model.stretch = .manual
    host.layoutSubtreeIfNeeded()
    let manual = host.fittingSize
    #expect(manual.height > empty.height, "manual shows a slider row per channel and the readout")

    model.stretch = .off
    model.hover(atView: SIMD2(-50, -50))
    host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.height < manual.height)
  }

  @Test("the histogram plot is empty without counts and draws each channel's colour with them")
  func testHistogramPlot() throws {
    func pixels(_ bins: [[Int]]) throws -> (red: Int, green: Int, blue: Int) {
      let renderer = ImageRenderer(content: HistogramView(bins: bins).frame(width: 64, height: 32))
      let image = try #require(
        renderer.nsImage?.cgImage(forProposedRect: nil, context: nil, hints: nil))
      let bitmap = NSBitmapImageRep(cgImage: image)
      var totals = (red: 0, green: 0, blue: 0)
      for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
          guard let colour = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
          totals.red += colour.redComponent > 0.3 ? 1 : 0
          totals.green += colour.greenComponent > 0.3 ? 1 : 0
          totals.blue += colour.blueComponent > 0.3 ? 1 : 0
        }
      }
      return totals
    }
    let none = try pixels([])
    #expect(none.red == 0 && none.green == 0 && none.blue == 0, "black background only")
    let full = [Int](repeating: 100, count: 256)
    let empty = [Int](repeating: 0, count: 256)
    let red = try pixels([full, empty, empty])
    #expect(red.red > 0 && red.green == 0, "only the red channel has counts")
  }
}
