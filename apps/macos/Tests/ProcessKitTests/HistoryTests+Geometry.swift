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

  /// Card 0090: a geometry step replaces bundle layers (`RGB`, `Ha`…) besides its image; they
  /// overlay the bundle until undone and survive a reopen. Its moved plate solution travels in
  /// the image's metadata: written in its files, carried by the steps after it (0093's rule).
  @Test("testReplacedLayersAndMovedWCSFollowTheStep", .scratchDirectory)
  func testReplacedLayersAndMovedWCSFollowTheStep() throws {
    let directory = try ScratchDirectory.url.appendingPathComponent("history")
    let header = try FITSFile.parse(Data(Self.solvedHeaderText.utf8)).header
    let original = try Self.image([0, 1, 2, 3])
    let history = try History(directory: directory, original: original, header: header)
    func cd11(_ step: Int) throws -> Double? {
      try FITSFile.read(at: directory.appendingPathComponent(history.steps[step].file)).header
        .double("CD1_1")
    }

    let moved = try #require(
      WCS(header: header.moved(by: GridMap.identity(width: 2, height: 2).flippedX())))
    let flipped = try Self.image([1, 0, 3, 2])
    flipped.metadata.wcs = moved
    try history.apply(
      processID: "geometry", params: Self.params, result: flipped,
      replacing: ["Ha": try Self.image([7, 7, 7, 7])])
    #expect(history.steps.last?.replaced.keys.sorted() == ["Ha"])
    #expect(try history.writtenLayers()["Ha"]?.planes == [[7, 7, 7, 7]])
    #expect(try cd11(0) == 2.0e-4, "the step's file carries the moved solution")
    #expect(history.current.metadata.wcs == moved)

    // A later step carries the head's solution on; a reopen finds the layers again.
    let next = history.current
    try history.apply(processID: "a", params: Self.params, result: next)
    #expect(try cd11(1) == 2.0e-4)
    let reopened = try History.reopen(
      directory: directory, original: original, header: header
    ) { _ in Self.gainSchema }
    #expect(reopened.steps == history.steps)
    #expect(try reopened.writtenLayers()["Ha"]?.planes == [[7, 7, 7, 7]])
    #expect(reopened.referencedFiles.contains { $0.hasSuffix("-Ha.fits") })
    try reopened.undo()
    try reopened.undo()
    #expect(try reopened.writtenLayers().isEmpty)
  }
}
