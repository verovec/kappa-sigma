import AppKit
import ImageKit
import Metal
import Observation
import RenderKit
import Testing

/// The AppKit layer: real `NSEvent`s into `ViewerMTKView` in an offscreen window, checked on
/// the model it drives; a real frame drawn into its drawable, checked on the histogram.
@MainActor
@Suite(
  "Viewer surface: events reach the model, frames reach the histogram",
  .enabled(if: GPU.available))
struct ViewerSurfaceTests {
  @MainActor
  struct Surface {
    let model: ViewerModel
    let view: ViewerMTKView
    let window: NSWindow
    /// Drawable pixels per point.
    var backing: Double { Double(window.backingScaleFactor) }
  }

  static func surface(width: Int = 64, height: Int = 32) throws -> Surface {
    let device = try GPU.requireDevice()
    let planes: [[Float]] = (0..<3).map { channel in
      (0..<width * height).map { Float(($0 + channel) % 50) / 50 }
    }
    let header = try ViewerTests.header([("ROWORDER", "'TOP-DOWN'")])
    let image = AstroImage(
      width: width, height: height, planes: planes, metadata: ImageMetadata(header: header))
    let model = ViewerModel(image: image)
    let view = ViewerMTKView(
      model: model, renderer: try ViewerRenderer(device: device),
      texture: try ImageTexture(device: device, width: width, height: height, planes: planes),
      reference: nil)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 100, height: 50), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.contentView = view
    return Surface(model: model, view: view, window: window)
  }

  /// A mouse event at a point in window coordinates (bottom-left origin).
  static func mouse(
    _ type: NSEvent.EventType, at point: NSPoint, in window: NSWindow, clicks: Int = 1
  ) throws -> NSEvent {
    try #require(
      NSEvent.mouseEvent(
        with: type, location: point, modifierFlags: [], timestamp: 0,
        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks,
        pressure: 1))
  }

  static func flags(_ flags: NSEvent.ModifierFlags, in window: NSWindow) throws -> NSEvent {
    try #require(
      NSEvent.keyEvent(
        with: .flagsChanged, location: .zero, modifierFlags: flags, timestamp: 0,
        windowNumber: window.windowNumber, context: nil, characters: "",
        charactersIgnoringModifiers: "", isARepeat: false, keyCode: 58))
  }

  @Test("the surface takes the keyboard: ⌘0 / ⌘1 reach it through the responder chain")
  func testResponderChainCommands() throws {
    let surface = try Self.surface()
    #expect(surface.window.firstResponder === surface.view)
    // The first drawable size (the window's, × the display's backing scale) fits the image.
    let first = surface.model.viewSize
    #expect(first == SIMD2(100, 50) * surface.backing)
    #expect(
      surface.model.frame.transform
        == .fit(imageWidth: 64, imageHeight: 32, viewWidth: first.x, viewHeight: first.y))
    // Later resizes keep the user's zoom; ⌘0 fits the new size.
    surface.view.mtkView(surface.view, drawableSizeWillChange: CGSize(width: 200, height: 100))
    #expect(surface.model.viewSize == SIMD2(200, 100))
    #expect(surface.model.frame.transform.scale == 64 / first.x)

    let responder = try #require(surface.window.firstResponder)
    #expect(responder.tryToPerform(#selector(ViewerMTKView.zoomToActualSize(_:)), with: nil))
    #expect(surface.model.frame.transform.scale == 1)
    #expect(responder.tryToPerform(#selector(ViewerMTKView.zoomToFit(_:)), with: nil))
    #expect(surface.model.frame.transform.scale == 0.32)
  }

  @Test("a drag pans with the pan tool and draws the region with the region tool")
  func testDragTools() throws {
    let surface = try Self.surface()
    let (view, window, model) = (surface.view, surface.window, surface.model)
    model.frame.transform = ViewTransform(scale: 1, origin: .zero)

    view.mouseDown(with: try Self.mouse(.leftMouseDown, at: NSPoint(x: 10, y: 40), in: window))
    view.mouseDragged(
      with: try Self.mouse(.leftMouseDragged, at: NSPoint(x: 14, y: 37), in: window))
    view.mouseUp(with: try Self.mouse(.leftMouseUp, at: NSPoint(x: 14, y: 37), in: window))
    // Window y grows upwards, view y downwards: the image follows the pointer.
    #expect(model.frame.transform.origin == SIMD2(-4, -3) * surface.backing)

    model.tool = .region
    model.frame.transform = ViewTransform(scale: 1, origin: .zero)
    view.mouseDown(with: try Self.mouse(.leftMouseDown, at: NSPoint(x: 2, y: 48), in: window))
    view.mouseDragged(with: try Self.mouse(.leftMouseDragged, at: NSPoint(x: 6, y: 45), in: window))
    let side = Int(surface.backing)
    #expect(
      model.frame.region == PixelRegion(x: 2 * side, y: 2 * side, width: 4 * side, height: 3 * side)
    )
    #expect(model.readout?.x == 6 * side)
    view.mouseDown(
      with: try Self.mouse(.leftMouseDown, at: NSPoint(x: 6, y: 45), in: window, clicks: 2))
    #expect(model.frame.region == nil, "double-click with the region tool clears it")
  }

  @Test("hovering reads the pixel; scrolling zooms; ⌥ shows the reference until the window resigns")
  func testHoverScrollAndCompareKey() throws {
    let surface = try Self.surface()
    let (view, window, model) = (surface.view, surface.window, surface.model)
    model.frame.transform = ViewTransform(scale: 1, origin: .zero)

    view.mouseMoved(with: try Self.mouse(.mouseMoved, at: NSPoint(x: 3.2, y: 48.6), in: window))
    let readout = try #require(model.readout)
    #expect(readout.x == Int(3.2 * surface.backing) && readout.y == Int(1.4 * surface.backing))

    let wheel = try #require(
      CGEvent(
        scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 2, wheel2: 0, wheel3: 0))
    view.scrollWheel(with: try #require(NSEvent(cgEvent: wheel)))
    #expect(model.frame.transform.scale < 1, "scrolling up magnifies")

    view.flagsChanged(with: try Self.flags(.option, in: window))
    #expect(model.frame.compare == .reference)
    NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
    #expect(model.frame.compare == .off, "⌥ released while away is not seen: dropped on resign")
    view.flagsChanged(with: try Self.flags([], in: window))
    #expect(!model.compareKeyHeld)
  }

  @Test("a drawn frame publishes the histogram of the region", .timeLimit(.minutes(1)))
  func testDrawPublishesHistogram() async throws {
    let surface = try Self.surface()
    surface.view.mtkView(surface.view, drawableSizeWillChange: surface.view.drawableSize)
    surface.model.frame.region = PixelRegion(x: 0, y: 0, width: 8, height: 4)
    surface.view.draw()
    let histogram = await Self.firstNonEmpty(surface.model)
    #expect(histogram.count == 3)
    #expect(histogram.allSatisfy { $0.reduce(0, +) == 8 }, "4 × 2 samples at stride 2")
  }

  /// The model's histogram once a frame has published one.
  static func firstNonEmpty(_ model: ViewerModel) async -> [[Int]] {
    for await histogram in Observations({ model.histogram }) where !histogram.isEmpty {
      return histogram
    }
    return []
  }
}
