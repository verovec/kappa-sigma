import Foundation
import ImageKit
import ProcessKit
import Testing

/// Card 0130: a catalogue object's position is offered next to the header's, never set; an image
/// that already carries a solution says where it points and at what scale.
@Suite("PlateSolveProcess: the catalogue's offer, the solution already there")
struct PlateSolveCatalogueTests {
  @Test("a catalogue object's RA/Dec, one suggestion each, the object named as the subject")
  func testSuggestionsFromCatalogueObject() {
    let suggestions = PlateSolveProcess.suggestions(
      object: "Sh2-132", raDeg: 334.698615, decDeg: 56.134831)
    let reason = PlateSolveProcess.fromCatalogue
    #expect(
      suggestions == [
        Suggestion(paramID: "ra", value: .text("334.698615"), reason: reason, subject: "Sh2-132"),
        Suggestion(paramID: "dec", value: .text("56.134831"), reason: reason, subject: "Sh2-132"),
      ])
    #expect(PlateSolveProcess.suggestionReasons.contains(reason))
  }

  static let solution = [
    "CTYPE1  = 'RA---TAN'", "CTYPE2  = 'DEC--TAN'", "CRPIX1  = 4.5", "CRPIX2  = 4.5",
    "CRVAL1  = 10.7032408167172", "CRVAL2  = 41.2714040033193", "CD1_1   = -1.7E-04",
    "CD1_2   = 8.5E-04", "CD2_1   = -8.5E-04", "CD2_2   = -1.7E-04",
  ]

  static func header(_ lines: [String]) throws -> FITSHeader {
    var text = lines.map { $0.padding(toLength: 80, withPad: " ", startingAt: 0) }.joined()
    text += "END"
    while text.utf8.count % 2880 != 0 { text += " " }
    return try FITSFile.parse(Data(text.utf8)).header
  }

  @Test("already solved: the centre pixel's RA/Dec and the scale from the CD matrix")
  func testAlreadySolvedLineFromWCS() throws {
    let wcs = try #require(WCS(header: try Self.header(Self.solution)))
    let status = try #require(PlateSolveStatus(wcs: wcs, width: 8, height: 8))
    #expect(abs(status.raDeg - 10.7032408167172) < 1e-9)
    #expect(abs(status.decDeg - 41.2714040033193) < 1e-9)
    // sqrt(|det CD|) = 8.668e-4° = 3.1206″/px.
    #expect(abs(status.arcsecPerPixel - 3.1206) < 1e-3)
    #expect(PlateSolveStatus(wcs: nil, width: 8, height: 8) == nil)
  }
}
