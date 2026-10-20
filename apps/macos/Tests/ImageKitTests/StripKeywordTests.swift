import Foundation
import ImageKit
import TestSupport
import Testing

/// `stripKeyword` is the legacy `fits.StripKeyword`: a linear master loses its BAYERPAT card in
/// place (blanked, so the header keeps its size) and nothing else in the file moves.
@Suite("FITSFile — keyword stripping in place")
struct StripKeywordTests {
  @Test(
    "every card with the keyword is blanked, the rest of the file is byte-identical",
    .scratchDirectory)
  func testStripKeyword_blanksInPlace() throws {
    let extra = [
      FITSBytes.card("BAYERPAT", "'RGGB    '"), FITSBytes.card("OBJECT", "'M31     '"),
      FITSBytes.card("bayerpat", "'GBRG    '"),
    ]
    let data = FITSBytes.float32(width: 2, height: 1, planes: [[1, 2]], extra: extra)
    let url = try ScratchDirectory.url.appendingPathComponent("master.fits")
    try data.write(to: url)
    try FITSFile.stripKeyword("BAYERPAT", at: url)
    let after = try Data(contentsOf: url)
    #expect(after.count == data.count)
    let file = try FITSFile.read(at: url)
    #expect(!file.header.cards.contains { $0.keyword.uppercased() == "BAYERPAT" })
    #expect(file.header.cards.contains { $0.keyword == "OBJECT" })
    #expect(try file.image().planes == [[1, 2]])
    let differing = zip(data, after).filter { $0 != $1 }
    #expect(!differing.isEmpty && differing.count <= 2 * 80)
  }

  @Test("a file without the keyword is untouched; a missing file is an error", .scratchDirectory)
  func testStripKeyword_absent() throws {
    let data = FITSBytes.float32(width: 1, height: 1, planes: [[3]])
    let url = try ScratchDirectory.url.appendingPathComponent("plain.fits")
    try data.write(to: url)
    try FITSFile.stripKeyword("BAYERPAT", at: url)
    #expect(try Data(contentsOf: url) == data)
    #expect(throws: (any Error).self) {
      try FITSFile.stripKeyword("BAYERPAT", at: url.appendingPathExtension("gone"))
    }
  }
}
