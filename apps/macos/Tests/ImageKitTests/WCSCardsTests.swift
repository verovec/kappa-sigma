import Foundation
import ImageKit
import Testing

/// Card 0093: a solution is carried as its header cards, so a file written from an image says
/// the image's WCS, not its source's.
@Suite("WCS cards: what a solution is written as")
struct WCSCardsTests {
  static let solved = WCSTests.header([
    ("OBJECT", "'M 31'"), ("CTYPE1", "'RA---TAN'"), ("CTYPE2", "'DEC--TAN'"),
    ("CRPIX1", "512.5"), ("CRPIX2", "384.5"), ("CRVAL1", "10.70324"), ("CRVAL2", "41.27140"),
    ("CDELT1", "-8.658E-04"), ("CDELT2", "8.657E-04"), ("PC1_1", "-0.2002"), ("PC1_2", "0.9797"),
    ("PC2_1", "-0.9797"), ("PC2_2", "-0.2002"), ("A_ORDER", "2"), ("A_2_0", "1E-07"),
    ("PLTSOLVD", "T"), ("FOCALLEN", "248.8"),
  ])
  static let stale = WCSTests.header([
    ("OBJECT", "'M 31'"), ("CTYPE1", "'RA---TAN'"), ("CTYPE2", "'DEC--TAN'"),
    ("CRPIX1", "2221.9"), ("CRPIX2", "418.3"), ("CRVAL1", "11.05"), ("CRVAL2", "39.81"),
    ("CD1_1", "1E-04"), ("CD1_2", "0"), ("CD2_1", "0"), ("CD2_2", "1E-04"), ("EXPTIME", "300."),
  ])

  @Test("the solution keeps its WCS cards in order, nothing else")
  func testCards() throws {
    let wcs = try #require(WCS(header: Self.solved))
    #expect(
      wcs.cards.map(\.keyword) == [
        "CTYPE1", "CTYPE2", "CRPIX1", "CRPIX2", "CRVAL1", "CRVAL2", "CDELT1", "CDELT2", "PC1_1",
        "PC1_2", "PC2_1", "PC2_2", "A_ORDER", "A_2_0", "PLTSOLVD",
      ])
  }

  @Test("a header takes another solution: its own WCS cards out, the new ones in")
  func testReplacingWCS() throws {
    let wcs = try #require(WCS(header: Self.solved))
    let header = Self.stale.carrying(wcs)
    #expect(header.cards.map(\.keyword) == ["OBJECT", "EXPTIME"] + wcs.cards.map(\.keyword))
    #expect(WCS(header: header) == wcs)
  }

  @Test("the header's own solution, or none at all, leaves it as it is")
  func testUnchanged() throws {
    let own = try #require(WCS(header: Self.stale))
    #expect(Self.stale.carrying(own) == Self.stale)
    let bare = WCSTests.header([("OBJECT", "'M 31'")])
    #expect(bare.carrying(nil) == bare)
  }

  @Test("an image without a solution drops the header's")
  func testDropped() {
    #expect(Self.stale.carrying(nil).cards.map(\.keyword) == ["OBJECT", "EXPTIME"])
  }
}
