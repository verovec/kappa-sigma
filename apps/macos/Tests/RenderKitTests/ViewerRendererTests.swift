import Metal
import RenderKit
import TestSupport
import Testing

@Suite(
  "ViewerRenderer: one frame = display + histogram in one command buffer",
  .enabled(if: GPU.available))
struct ViewerRendererTests {
  @Test("a frame shows the view transform and counts the region (or the whole image)")
  func testFrameDisplaysAndCounts() throws {
    let device = try GPU.requireDevice()
    let plane = (0..<16).map { Float($0) / 15 }
    let image = try ImageTexture(device: device, width: 4, height: 4, planes: [plane])
    let renderer = try ViewerRenderer(device: device)
    let output = try GPU.output(width: 2, height: 2)

    var frame = ViewerFrame(transform: ViewTransform(scale: 1, origin: SIMD2(2, 2)), stf: nil)
    var bins = try renderer.render(image: image, reference: nil, frame: frame, into: output)
    #expect(GPU.read(output).map(\.x) == [plane[10], plane[11], plane[14], plane[15]])
    #expect(bins[0].reduce(0, +) == 4, "whole image at stride 2")

    frame.region = PixelRegion(x: 1, y: 1, width: 2, height: 1)
    bins = try renderer.render(image: image, reference: nil, frame: frame, into: output)
    #expect(bins[0].reduce(0, +) == 1)
    #expect(bins[0][Int(plane[5] * 255 + 0.5)] == 1)
  }

  @Test("a timed frame reports the GPU time it took")
  func testRenderTimed() throws {
    let device = try GPU.requireDevice()
    let image = try ImageTexture(
      device: device, width: 4, height: 4, planes: [[Float](repeating: 0.5, count: 16)])
    let frame = ViewerFrame(transform: ViewTransform(scale: 1, origin: .zero), stf: nil)
    let seconds = try ViewerRenderer(device: device).renderTimed(
      image: image, frame: frame, into: try GPU.output(width: 4, height: 4))
    #expect(seconds > 0 && seconds < 1)
  }

  @Test("the compare frame selects the reference with its split")
  func testCompareFrame() throws {
    let device = try GPU.requireDevice()
    let current = try ImageTexture(device: device, width: 2, height: 1, planes: [[0.5, 0.5]])
    let reference = try ImageTexture(device: device, width: 2, height: 1, planes: [[0.25, 0.25]])
    let renderer = try ViewerRenderer(device: device)
    let output = try GPU.output(width: 2, height: 1)
    var frame = ViewerFrame(transform: ViewTransform(scale: 1, origin: .zero), stf: nil)
    frame.compare = .split(atViewX: 1)
    _ = try renderer.render(image: current, reference: reference, frame: frame, into: output)
    #expect(GPU.read(output).map(\.x) == [0.25, 0.5])
    frame.compare = .reference
    _ = try renderer.render(image: current, reference: reference, frame: frame, into: output)
    #expect(GPU.read(output).map(\.x) == [0.25, 0.25])
  }
}

/// Frame budget on the target GPU only (the hosted runner's GPU is paravirtualised): live suite.
@Suite(
  "Live viewer frame budget", .liveFixtures, .tags(.live), .serialized,
  .enabled(if: GPU.available), .timeLimit(.minutes(2)))
struct LiveViewerPerfTests {
  @Test("60 frames of a 22 Mpx RGB image with STF on and the histogram average ≤ 16 ms GPU time")
  func testFrameBudget22Mpx() throws {
    let device = try GPU.requireDevice()
    let (width, height) = (5760, 3840)
    let planes: [[Float]] = (0..<3).map { channel in
      (0..<width * height).map { Float(($0 &* 2_654_435_761 &+ channel) % 65_536) / 65_536 }
    }
    let image = try ImageTexture(device: device, width: width, height: height, planes: planes)
    let renderer = try ViewerRenderer(device: device)
    let output = try GPU.output(width: 3024, height: 1964)
    let stf = AutoSTF.compute(planes: planes, linked: false)
    var frame = ViewerFrame(
      transform: .fit(imageWidth: width, imageHeight: height, viewWidth: 3024, viewHeight: 1964),
      stf: stf)
    var seconds: [Double] = []
    for index in 0..<60 {
      // Zoom between fit and 1:1, as a user would.
      frame.transform.scale = 1 + Double(index % 10) * 0.2
      seconds.append(try renderer.renderTimed(image: image, frame: frame, into: output))
    }
    let average = seconds.reduce(0, +) / Double(seconds.count) * 1000
    let worst = (seconds.max() ?? 0) * 1000
    print("ViewerPerf: 22 Mpx RGB, 3024×1964 view, mean GPU \(average) ms, max \(worst) ms")
    #expect(average <= 16)
  }
}
