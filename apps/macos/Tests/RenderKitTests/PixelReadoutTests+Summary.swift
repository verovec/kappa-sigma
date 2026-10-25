import AppKit
import Foundation
import ImageKit
import RenderKit
import Testing

/// The readout on one line, as the full-screen HUD shows it (card 0127): the View panel's words
/// and digits, in the viewer's language.
@MainActor
@Suite("PixelReadout.summary — the HUD's one-line readout")
struct PixelReadoutSummaryTests {
  @Test(
    "pixel, channels and sky in each language",
    arguments: [
      ("en", 3, "2, 1 · R 0.120000 G 0.120000 B 0.120000 · RA "),
      ("fr", 3, "2, 1 · R 0,120000 G 0,120000 B 0,120000 · AD "),
      ("fr", 1, "2, 1 · K 0,120000 · AD "),
    ])
  func testSummary(language: String, planes: Int, prefix: String) throws {
    let model = try ViewerViewTests.model(planes: planes)
    let image = AstroImage(
      width: 8, height: 8,
      planes: Array(repeating: [Float](repeating: 0.12, count: 64), count: planes),
      metadata: model.image.metadata)
    let readout = try #require(PixelReadout(image: image, x: 2, y: 1))
    let summary = readout.summary(locale: Locale(identifier: language))
    #expect(summary.hasPrefix(prefix), "\(summary)")
    #expect(summary.contains(language == "fr" ? " Déc " : " Dec "))
  }

  @Test("without a plate solution the line stops at the channels")
  func testSummary_NoSky() throws {
    let header = try ViewerTests.header([("ROWORDER", "'TOP-DOWN'")])
    let image = AstroImage(
      width: 2, height: 2, planes: [[0.5, 0.5, 0.5, 0.5]], metadata: ImageMetadata(header: header))
    let readout = try #require(PixelReadout(image: image, x: 1, y: 0))
    #expect(readout.summary(locale: Locale(identifier: "en")) == "1, 0 · K 0.500000")
  }

  @Test("the window's own full screen reads its style mask")
  func testWindowFullScreen_ReadsStyleMask() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: [.titled],
      backing: .buffered, defer: false)
    #expect(!ViewerFullScreen.window.isOn(window))
  }
}
