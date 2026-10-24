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

// MARK: - A move never keeps a solution it cannot move (card 0106)

extension HistoryTests {
  /// A header of `cards` (`KEYWORD = value`), OBJECT and the row order first.
  static func header(_ cards: [String]) throws -> FITSHeader {
    var text =
      (["OBJECT  = 'M31'", "ROWORDER= 'TOP-DOWN'"] + cards)
      .map { $0.padding(toLength: 80, withPad: " ", startingAt: 0) }.joined() + "END"
    while text.utf8.count % 2880 != 0 { text += " " }
    return try FITSFile.parse(Data(text.utf8)).header
  }

  /// An alternate TAN solution (`…A`): readers ignore it, a move cannot keep it.
  static let alternateCards = [
    "WCSAXESA= 2", "CTYPE1A = 'RA---TAN'", "CTYPE2A = 'DEC--TAN'", "CRPIX1A = 1.5",
    "CRPIX2A = 1.5", "CRVAL1A = 10.68", "CRVAL2A = 41.27", "CD1_1A  = -2.0E-4",
    "CD2_2A  = 2.0E-4", "WCSNAMEA= 'alt'",
  ]
  static let zeaCards = [
    "CTYPE1  = 'RA---ZEA'", "CTYPE2  = 'DEC--ZEA'", "CRPIX1  = 1.5", "CRPIX2  = 1.5",
    "CRVAL1  = 10.68", "CRVAL2  = 41.27", "CDELT1  = -2.0E-4", "CDELT2  = 2.0E-4",
  ]
  static let sipCards = [
    "CTYPE1  = 'RA---TAN-SIP'", "CTYPE2  = 'DEC--TAN-SIP'", "CRPIX1  = 1.2", "CRPIX2  = 1.7",
    "CRVAL1  = 10.68", "CRVAL2  = 41.27", "CD1_1   = -2.1E-4", "CD1_2   = 3.0E-5",
    "CD2_1   = 2.5E-5", "CD2_2   = 2.0E-4", "A_ORDER = 2", "B_ORDER = 2", "A_2_0   = 1.0E-3",
    "B_1_1   = -2.0E-4", "PLTSOLVD= T",
  ]

  /// The header of the file step `index` of `history` wrote.
  static func header(of history: History, step index: Int) throws -> FITSHeader {
    try FITSFile.read(at: history.directory.appendingPathComponent(history.steps[index].file))
      .header
  }

  @Test("testMoveDropsUnmovableSolutions", .scratchDirectory, arguments: [false, true])
  func testMoveDropsUnmovableSolutions(sip: Bool) throws {
    let directory = try ScratchDirectory.url.appendingPathComponent("history")
    let header = try Self.header((sip ? Self.sipCards : Self.zeaCards) + Self.alternateCards)
    let original = AstroImage(
      width: 2, height: 2, planes: [[0, 1, 2, 3]], metadata: ImageMetadata(header: header))
    #expect((original.metadata.wcs != nil) == sip, "only TAN-SIP is read as a solution")
    let history = try History(directory: directory, original: original, header: header)
    let map = GridMap.identity(width: 2, height: 2).flippedX()
    let moved = WCS(header: header.moved(by: map))
    let flipped = AstroImage(
      width: 2, height: 2, planes: [[1, 0, 3, 2]], metadata: original.metadata)
    flipped.metadata.wcs = moved

    try history.apply(
      processID: "geometry", params: Self.params, result: flipped, movesPixels: true)
    try history.apply(processID: "a", params: Self.params, result: history.current)
    for step in 0..<2 {
      let written = try Self.header(of: history, step: step)
      #expect(written.cards.allSatisfy { FITSHeader.solutionKeyword($0.keyword) != .alternate })
      #expect(written.string("OBJECT") == "M31")
      #expect(written.string("CTYPE1") == (sip ? "RA---TAN-SIP" : nil), "step \(step)")
      #expect(WCS(header: written) == moved, "step \(step)")
    }
    // Every star keeps its RA/Dec (the 0090 oracle, through the file).
    if let before = original.metadata.wcs {
      let after = try #require(WCS(header: try Self.header(of: history, step: 1)))
      for (x, y) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
        let out = map.output(ofInput: SIMD2(x, y))
        let (ra, dec) = before.sky(x: Double(x), y: Double(y))
        let (ra2, dec2) = after.sky(x: Double(out.x), y: Double(out.y))
        #expect(abs(ra - ra2) < 1e-9 && abs(dec - dec2) < 1e-9, "\(x),\(y)")
      }
    }
  }

  @Test("testUnmovedStepsKeepTheHeader", .scratchDirectory)
  func testUnmovedStepsKeepTheHeader() throws {
    let root = try ScratchDirectory.url
    let directory = root.appendingPathComponent("history")
    let header = try Self.header(Self.sipCards + Self.alternateCards)
    let original = AstroImage(
      width: 2, height: 2, planes: [[0, 1, 2, 3]], metadata: ImageMetadata(header: header))
    let history = try History(directory: directory, original: original, header: header)
    let result = AstroImage(
      width: 2, height: 2, planes: [[4, 5, 6, 7]], metadata: original.metadata)

    try history.apply(processID: "a", params: Self.params, result: result)
    // Byte-identical to what every step wrote before card 0106: the alternate solution stays.
    let today = root.appendingPathComponent("today.fits")
    try FITSFile.create(result, keeping: header.carrying(result.metadata.wcs), at: today)
    let written = directory.appendingPathComponent(history.steps[0].file)
    #expect(try Data(contentsOf: written) == Data(contentsOf: today))
    #expect(try Self.header(of: history, step: 0).string("WCSNAMEA") == "alt")
    let manifest = directory.deletingLastPathComponent().appendingPathComponent("history.json")
    let text = try #require(String(bytes: try Data(contentsOf: manifest), encoding: .utf8))
    #expect(!text.contains("movesPixels"), "a step that moves nothing writes no new key")

    try history.apply(processID: "a", params: Self.params, result: result, movesPixels: true)
    #expect(history.steps.map(\.movesPixels) == [false, true])
    let reopened = try History.reopen(
      directory: directory, original: original, header: header
    ) { _ in Self.gainSchema }
    #expect(reopened.steps == history.steps)
    #expect(reopened.steps.map(\.movesPixels) == [false, true])
  }

  /// A manifest written before card 0106 records no move: reopened, a step's move is told by
  /// the registry's rule, so the steps after a recorded flip still drop the stale solutions.
  @Test("testReopenTellsAnOldMove", .scratchDirectory)
  func testReopenTellsAnOldMove() throws {
    let directory = try ScratchDirectory.url.appendingPathComponent("history")
    let header = try Self.header(Self.zeaCards + Self.alternateCards)
    let original = AstroImage(
      width: 2, height: 2, planes: [[0, 1, 2, 3]], metadata: ImageMetadata(header: header))
    let old = try History(directory: directory, original: original, header: header)
    try old.apply(processID: "geometry", params: Self.params, result: original)
    #expect(old.steps.map(\.movesPixels) == [false], "as a pre-0106 manifest records it")

    let reopened = try History.reopen(
      directory: directory, original: original, header: header,
      movesPixels: { id, _ in id == "geometry" }, schema: { _ in Self.gainSchema })
    #expect(reopened.steps.map(\.movesPixels) == [true])
    try reopened.apply(processID: "a", params: Self.params, result: reopened.current)
    let written = try Self.header(of: reopened, step: 1)
    #expect(written.cards.allSatisfy { FITSHeader.solutionKeyword($0.keyword) == nil })
  }
}
