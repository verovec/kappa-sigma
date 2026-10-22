import Foundation
import ImageKit
import ProcessKit
import TestSupport
import Testing

/// Card 0093: a step that adds a plate solution writes it in its own file; the steps after it,
/// undo, redo and a reopened history read it back.
@Suite("History: a step's WCS is its own")
struct HistoryWCSTests {
  static let solvedHeader = """
    CTYPE1  = 'RA---TAN'
    CTYPE2  = 'DEC--TAN'
    CRPIX1  = 1.5
    CRPIX2  = 1.5
    CRVAL1  = 10.70324
    CRVAL2  = 41.2714
    CD1_1   = -1.7E-04
    CD1_2   = 8.5E-04
    CD2_1   = -8.5E-04
    CD2_2   = -1.7E-04
    """

  static func solved(_ values: [Float]) throws -> AstroImage {
    var cards = solvedHeader.split(separator: "\n").map {
      String($0).padding(toLength: 80, withPad: " ", startingAt: 0)
    }.joined()
    cards += "END"
    while cards.utf8.count % 2880 != 0 { cards += " " }
    let image = try HistoryTests.image(values)
    image.metadata.wcs = WCS(header: try FITSFile.parse(Data(cards.utf8)).header)
    return image
  }

  @Test(
    "solve, then a GPU-like step: both files carry it; undo, redo, reopen read it",
    .scratchDirectory)
  func testWCSFollowsSteps() throws {
    let directory = try ScratchDirectory.url.appendingPathComponent("history")
    let original = try HistoryTests.image([0, 1, 2, 3])
    let header = try FITSFile.parse(Data(HistoryTests.headerText.utf8)).header
    let history = try History(directory: directory, original: original, header: header)
    let solved = try Self.solved([0, 1, 2, 3])
    let wcs = try #require(solved.metadata.wcs)

    try history.apply(processID: "solve", params: HistoryTests.params, result: solved)
    let next = history.current
    next.planes = [[1, 2, 3, 4]]
    try history.apply(processID: "gain", params: HistoryTests.params, result: next)
    for step in history.steps {
      let file = try FITSFile.read(at: directory.appendingPathComponent(step.file))
      #expect(WCS(header: file.header) == wcs, "\(step.processID) wrote the solution")
      #expect(file.header.string("OBJECT") == "M31", "the source's other cards stay")
    }
    try history.undo()
    try history.undo()
    #expect(history.current.metadata.wcs == nil, "the original has no solution")
    try history.redo()
    #expect(history.current.metadata.wcs == wcs)
    let schema = ParamSchema([
      ParamSpec(id: "gain", title: "Gain", unit: .none, level: .simple, number: 1, in: 0...8)
    ])
    let reopened = try History.reopen(
      directory: directory, original: original, header: header, schema: { _ in schema })
    #expect(reopened.current.metadata.wcs == wcs)
  }
}
