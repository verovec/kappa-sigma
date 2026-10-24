import RenderKit
import Testing

@Suite("ViewerFrame: what the panel says about the frame")
struct ViewerFrameTests {
  /// Card 0110: the clipping overlay judges the filtered value only zoomed out; the panel says so
  /// then, and only then.
  @Test(
    "the clipping overlay is on the average only when it is on and the view is zoomed out",
    arguments: [
      (overlay: true, scale: 1.5, average: true),
      (overlay: true, scale: 1.0, average: false),
      (overlay: true, scale: 0.5, average: false),
      (overlay: false, scale: 3.0, average: false),
    ])
  func testClipsOnTheAverage(overlay: Bool, scale: Double, average: Bool) {
    var frame = ViewerFrame(transform: ViewTransform(scale: scale, origin: .zero), stf: nil)
    frame.clippingOverlay = overlay
    #expect(frame.clipsOnTheAverage == average)
  }
}
