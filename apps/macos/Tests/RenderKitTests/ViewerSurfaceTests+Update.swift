import AppKit
import ImageKit
import Metal
import RenderKit
import SwiftUI
import Testing

/// A `ViewerView` given new inputs by SwiftUI (`updateNSView`): the surface it keeps draws them,
/// not the ones it was created with (card 0109).
@MainActor
@Suite("Viewer surface: new inputs from SwiftUI are drawn", .enabled(if: GPU.available))
struct ViewerSurfaceUpdateTests {
  /// A hosted viewer and the inputs it was built with.
  @MainActor
  struct Hosted {
    let host: NSHostingView<ViewerView>
    let model: ViewerModel
    let renderer: ViewerRenderer
    let device: MTLDevice

    /// The Metal surface SwiftUI keeps inside the host.
    var surface: ViewerMTKView? { Self.find(in: host) }

    /// Gives the viewer new inputs, as a parent view's body does, and lets SwiftUI update.
    func update(texture: ImageTexture, reference: ImageTexture? = nil, mask: MTLTexture? = nil) {
      host.rootView = ViewerView(
        model: model, renderer: renderer, texture: texture, reference: reference, mask: mask)
      host.layoutSubtreeIfNeeded()
    }

    private static func find(in view: NSView) -> ViewerMTKView? {
      if let surface = view as? ViewerMTKView { return surface }
      for child in view.subviews {
        if let surface = find(in: child) { return surface }
      }
      return nil
    }
  }

  static func image(width: Int = 16, height: Int = 8, value: Float) throws -> AstroImage {
    let header = try ViewerTests.header([("ROWORDER", "'TOP-DOWN'")])
    let plane = [Float](repeating: value, count: width * height)
    return AstroImage(
      width: width, height: height, planes: [plane, plane, plane],
      metadata: ImageMetadata(header: header))
  }

  static func texture(_ image: AstroImage, device: MTLDevice) throws -> ImageTexture {
    try ImageTexture(device: device, width: image.width, height: image.height, planes: image.planes)
  }

  static func hosted(_ image: AstroImage) throws -> (Hosted, ImageTexture) {
    let device = try GPU.requireDevice()
    let model = ViewerModel(image: image)
    let renderer = try ViewerRenderer(device: device)
    let texture = try texture(image, device: device)
    let host = NSHostingView(
      rootView: ViewerView(model: model, renderer: renderer, texture: texture, reference: nil))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 900, height: 500), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    return (Hosted(host: host, model: model, renderer: renderer, device: device), texture)
  }

  /// The histogram a frame of `surface` publishes once drawn.
  static func drawnHistogram(_ surface: ViewerMTKView, _ model: ViewerModel) async -> [[Int]] {
    model.histogram = []
    surface.draw()
    return await ViewerSurfaceTests.firstNonEmpty(model)
  }

  @Test("a new texture is the one drawn, and its histogram is counted", .timeLimit(.minutes(1)))
  func testNewTexture_IsDrawn() async throws {
    let first = try Self.image(value: 0.1)
    let (hosted, _) = try Self.hosted(first)
    let surface = try #require(hosted.surface)
    let before = await Self.drawnHistogram(surface, hosted.model)

    let second = try Self.image(value: 0.9)
    let texture = try Self.texture(second, device: hosted.device)
    // The model is left as is: only the reset of the counted histogram can make it count again
    // (a new image's stretch would change the histogram's input by itself).
    hosted.update(texture: texture)

    #expect(hosted.surface === surface, "the surface is kept: zoom, focus and ⌥ survive")
    #expect(surface.texture === texture)
    let after = await Self.drawnHistogram(surface, hosted.model)
    #expect(after != before, "the frame counts the new image, not the first one")
  }

  @Test("a new compare reference and a new mask reach the surface")
  func testNewReferenceAndMask_ReachSurface() throws {
    let image = try Self.image(value: 0.4)
    let (hosted, texture) = try Self.hosted(image)
    let surface = try #require(hosted.surface)
    #expect(surface.reference == nil && surface.mask == nil)

    let reference = try Self.texture(try Self.image(value: 0.2), device: hosted.device)
    let mask = try #require(
      hosted.device.makeTexture(
        descriptor: .texture2DDescriptor(
          pixelFormat: .r32Float, width: 16, height: 8, mipmapped: false)))
    hosted.update(texture: texture, reference: reference, mask: mask)
    #expect(surface.reference === reference)
    #expect(surface.mask === mask)

    hosted.update(texture: texture)
    #expect(surface.reference == nil && surface.mask == nil, "compare and mask dropped")
  }

  @Test("the same inputs again change nothing on the surface")
  func testSameInputs_NoChange() throws {
    let (hosted, texture) = try Self.hosted(try Self.image(value: 0.5))
    let surface = try #require(hosted.surface)
    #expect(!surface.show(texture: texture, reference: nil, mask: nil))
    let other = try Self.texture(try Self.image(value: 0.7), device: hosted.device)
    #expect(surface.show(texture: other, reference: nil, mask: nil))
  }
}
