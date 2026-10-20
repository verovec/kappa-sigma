import Foundation
import ImageKit
import TestSupport
import Testing

@Suite("FITSFile.create: a new float32 file keeping the source's descriptive cards")
struct FITSCreateTests {
  static func source() throws -> FITSFile {
    // A 16-bit source header (its BITPIX/BZERO must not leak into the float32 file).
    try FITSFile.parse(
      FITSBytes.header([
        FITSBytes.card("SIMPLE", "T"), FITSBytes.card("BITPIX", "16"), FITSBytes.card("NAXIS", "2"),
        FITSBytes.card("NAXIS1", "2"), FITSBytes.card("NAXIS2", "1"),
        FITSBytes.card("BZERO", "32768"), FITSBytes.card("OBJECT", "'M31'"),
        FITSBytes.card("ROWORDER", "'TOP-DOWN'"), FITSBytes.card("CTYPE1", "'RA---TAN'"),
        FITSBytes.card("CHECKSUM", "'aBcD1234'"), FITSBytes.card("DATASUM", "'12345'"),
        FITSBytes.card("DATAMIN", "0"), FITSBytes.card("DATAMAX", "65535"),
      ]))
  }

  @Test(
    "planes, size and descriptive cards survive; structural cards are the new file's",
    .scratchDirectory)
  func testCreateKeepsDescriptiveCards() throws {
    let url = try ScratchDirectory.url.appendingPathComponent("step-1.fits")
    let planes: [[Float]] = [
      [0.25, -1, 3, 0.5, 0, 1], [1, 2, 3, 4, 5, 6], [0, 0, 0, 0, 0, 0.125],
    ]
    let header = try Self.source().header
    let image = AstroImage(
      width: 3, height: 2, planes: planes, metadata: ImageMetadata(header: header))

    try FITSFile.create(image, keeping: header, at: url)

    let file = try FITSFile.read(at: url)
    let reread = try file.image()
    #expect(reread.width == 3 && reread.height == 2 && reread.planes == planes)
    #expect(file.header.int("BITPIX") == -32 && file.header.int("NAXIS3") == 3)
    #expect(file.header.string("OBJECT") == "M31" && file.header.string("CTYPE1") == "RA---TAN")
    #expect(reread.metadata.rowOrder == .topDown)
    #expect(file.header.cards.filter { $0.keyword == "BITPIX" }.count == 1, "no stale BITPIX 16")
    #expect(file.header.double("BZERO") == nil, "a float32 file has no scaling")
    for stale in ["CHECKSUM", "DATASUM", "DATAMIN", "DATAMAX"] {
      #expect(file.header.string(stale) == nil, "\(stale) describes the old data")
    }
    #expect(file.header.cards[1].raw.hasPrefix("BITPIX  =                  -32"), "fixed format")
  }

  @Test("without a source header, the row order still comes from the image", .scratchDirectory)
  func testCreateWithoutHeader() throws {
    let url = try ScratchDirectory.url.appendingPathComponent("plain.fits")
    var metadata = try ImageMetadata(header: Self.source().header)
    metadata.rowOrder = .topDown
    try FITSFile.create(
      AstroImage(width: 2, height: 1, planes: [[1, 2]], metadata: metadata), keeping: nil, at: url)
    let reread = try FITSFile.read(at: url).image()
    #expect(reread.planes == [[1, 2]] && reread.metadata.rowOrder == .topDown)
  }
}
