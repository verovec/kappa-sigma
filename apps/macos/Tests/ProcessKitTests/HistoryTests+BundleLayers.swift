import Foundation
import ImageKit
import ProcessKit
import TestSupport
import Testing

extension HistoryTests {
  static let solvedHeaderText: String = {
    var text =
      [
        "OBJECT  = 'M31'", "ROWORDER= 'TOP-DOWN'", "CTYPE1  = 'RA---TAN'", "CTYPE2  = 'DEC--TAN'",
        "CRPIX1  = 1.5", "CRPIX2  = 1.5", "CRVAL1  = 10.68", "CRVAL2  = 41.27",
        "CD1_1   = -2.0E-4", "CD1_2   = 0.0", "CD2_1   = 0.0", "CD2_2   = 2.0E-4",
      ]
      .map { $0.padding(toLength: 80, withPad: " ", startingAt: 0) }.joined() + "END"
    while text.utf8.count % 2880 != 0 { text += " " }
    return text
  }()

  /// Card 0090: a geometry step rewrites bundle layers (`RGB`, `Ha`…) besides its image and its
  /// header (the plate solution moved); they overlay the bundle until undone, survive a reopen,
  /// and later steps keep the head's header, not the original's.
  @Test("testBundleLayersAndHeaderFollowTheStep", .scratchDirectory)
  func testBundleLayersAndHeaderFollowTheStep() throws {
    let directory = try ScratchDirectory.url.appendingPathComponent("history")
    let header = try FITSFile.parse(Data(Self.solvedHeaderText.utf8)).header
    let original = try Self.image([0, 1, 2, 3])
    let history = try History(directory: directory, original: original, header: header)
    #expect(try history.headHeader()?.double("CRPIX1") == 1.5)

    let moved = header.moved(by: GridMap.identity(width: 2, height: 2).flippedX())
    try history.apply(
      processID: "geometry", params: Self.params, result: try Self.image([1, 0, 3, 2]),
      bundleLayers: ["Ha": try Self.image([7, 7, 7, 7])], header: moved)
    #expect(history.steps.last?.bundleLayers.keys.sorted() == ["Ha"])
    #expect(try history.bundleLayers()["Ha"]?.planes == [[7, 7, 7, 7]])
    #expect(try history.headHeader()?.double("CRPIX1") == 1.5, "flipped about the centre")
    #expect(try history.headHeader()?.double("CD1_1") == 2.0e-4)
    #expect(history.current.metadata.wcs == WCS(header: moved), "the head carries the moved WCS")

    // A later step keeps the head's header; undoing the geometry gives the original back.
    try history.apply(processID: "a", params: Self.params, result: try Self.image([2, 2, 2, 2]))
    #expect(try history.headHeader()?.double("CD1_1") == 2.0e-4)
    #expect(try history.bundleLayers()["Ha"]?.planes == [[7, 7, 7, 7]])
    let reopened = try History.reopen(
      directory: directory, original: original, header: header
    ) { _ in Self.gainSchema }
    #expect(reopened.steps == history.steps)
    #expect(try reopened.bundleLayers()["Ha"]?.planes == [[7, 7, 7, 7]])
    #expect(reopened.referencedFiles.contains { $0.hasSuffix("-Ha.fits") })
    try reopened.undo()
    try reopened.undo()
    #expect(try reopened.bundleLayers().isEmpty)
    #expect(try reopened.headHeader()?.double("CD1_1") == -2.0e-4)
  }
}
