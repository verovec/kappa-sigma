import AppKit
import AstroStackApp
import Foundation
import ImageKit
import Metal
import RenderKit
import TestSupport
import Testing

@MainActor
@Suite(
  "ImageViewerWindow: File › Open Image… shows a FITS in the viewer",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct ImageViewerWindowTests {
  /// A 4×2 three-plane float32 FITS, bottom-up (the FITS default), from the standard's bytes.
  static func fits(at url: URL) throws {
    func card(_ key: String, _ value: String) -> String {
      (key.padding(toLength: 8, withPad: " ", startingAt: 0) + "= " + value)
        .padding(toLength: 80, withPad: " ", startingAt: 0)
    }
    var text =
      [
        card("SIMPLE", "T"), card("BITPIX", "-32"), card("NAXIS", "3"), card("NAXIS1", "4"),
        card("NAXIS2", "2"), card("NAXIS3", "3"),
      ].joined() + "END"
    while text.utf8.count % 2880 != 0 { text += " " }
    var data = Data(text.utf8)
    for index in 0..<24 {
      withUnsafeBytes(of: (Float(index) / 24).bitPattern.bigEndian) { data.append(contentsOf: $0) }
    }
    while data.count % 2880 != 0 { data.append(0) }
    try data.write(to: url)
  }

  @Test(
    "a FITS opens in a titled window with its image, rows flipped; closing forgets it",
    .scratchDirectory)
  func testOpenAndClose() async throws {
    let url = try ScratchDirectory.url.appendingPathComponent("M31.fits")
    try Self.fits(at: url)

    let controller = try await ImageViewerWindow.open(url)
    let window = try #require(controller.window)
    #expect(window.title == "M31.fits")
    let model = try #require(controller.model)
    #expect(model.image.width == 4 && model.image.height == 2 && model.image.planes.count == 3)
    #expect(model.frame.flipRows, "no ROWORDER: bottom-up, shown flipped")
    #expect(model.frame.stf == AutoSTF.compute(planes: model.image.planes, linked: false))
    #expect(ImageViewerWindow.openWindows.contains { $0 === controller })

    window.close()
    #expect(!ImageViewerWindow.openWindows.contains { $0 === controller })
  }

  @Test("Open Image… (show) opens the window off the main actor", .scratchDirectory)
  func testShowOpensWindow() async throws {
    let url = try ScratchDirectory.url.appendingPathComponent("IC1848.fits")
    try Self.fits(at: url)
    await ImageViewerWindow.show(url).value
    let controller = try #require(
      ImageViewerWindow.openWindows.first { $0.window?.title == "IC1848.fits" })
    #expect(controller.window?.title == "IC1848.fits")
    controller.window?.close()
  }

  @Test("the image picker accepts FITS files only, one at a time")
  func testImagePanel() {
    let panel = ImageViewerWindow.imagePanel()
    #expect(!panel.allowsMultipleSelection)
    #expect(
      Set(panel.allowedContentTypes.compactMap(\.preferredFilenameExtension)).isSuperset(of: [
        "fits"
      ]))
  }

  @Test("Open Image… on a file that is not FITS reports the error", .scratchDirectory)
  func testShowReportsFailure() async throws {
    let url = try ScratchDirectory.url.appendingPathComponent("broken.fits")
    try Data("nope".utf8).write(to: url)
    var reported = 0
    await ImageViewerWindow.show(url) { _ in reported += 1 }.value
    #expect(reported == 1)
  }

  @Test("a file that is not FITS is an error, and no window opens", .scratchDirectory)
  func testOpenRefusesNonFITS() async throws {
    let url = try ScratchDirectory.url.appendingPathComponent("notes.fits")
    try Data("not a FITS file".utf8).write(to: url)
    await #expect(throws: (any Error).self) { _ = try await ImageViewerWindow.open(url) }
    #expect(!ImageViewerWindow.openWindows.contains { $0.window?.title == "notes.fits" })
  }
}
