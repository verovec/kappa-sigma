import Foundation
import ImageKit
import TestSupport
import Testing

/// Capture software writes Latin-1 or UTF-8 bytes in header comments (`°C`, an accented
/// OBSERVER); Siril reads those files, so AstroStack must too. A file whose FIRST card is not
/// ASCII is still not a FITS file.
extension FITSFileTests {
  /// A float32 header whose `@` placeholders are replaced by `bytes`, one per `@`.
  static func header(cards: [String], replacing bytes: [UInt8]) -> Data {
    var data = FITSBytes.float32(width: 2, height: 1, planes: [[0.25, 0.5]], extra: cards)
    var next = bytes.makeIterator()
    for index in data.indices where data[index] == UInt8(ascii: "@") {
      guard let byte = next.next() else { break }
      data[index] = byte
    }
    return data
  }

  @Test(
    "non-ASCII bytes in a comment or value are read as '?', the card stays 80 columns",
    .scratchDirectory,
    arguments: [
      ("Latin-1 degree", [UInt8(0xB0)]),
      ("UTF-8 degree", [UInt8(0xC2), 0xB0]),
      ("control byte", [UInt8(0x09)]),
    ])
  func testFITSFile_read_toleratesNonASCIICards(name: String, bytes: [UInt8]) throws {
    let placeholder = String(repeating: "@", count: bytes.count)
    let url = try Self.write(
      Self.header(
        cards: [
          FITSBytes.card("CCD-TEMP", "-20.0 / sensor temperature in \(placeholder)C"),
          FITSBytes.card("OBSERVER", "'J\(placeholder)r'"),
          FITSBytes.card("FILTER", "'B'"), FITSBytes.card("EXPTIME", "15.0"),
        ],
        replacing: bytes + bytes),
      named: "b.fit")

    let file = try FITSFile.read(at: url)
    #expect(file.header.string("FILTER") == "B", "\(name)")
    #expect(file.header.double("EXPTIME") == 15)
    #expect(file.header.double("CCD-TEMP") == -20)
    #expect(
      file.header.string("OBSERVER") == "J" + String(repeating: "?", count: bytes.count) + "r")
    #expect(file.header.cards.allSatisfy { $0.raw.utf8.count == 80 })
    #expect(try file.image().planes == [[0.25, 0.5]], "the data unit starts where it did")
  }

  @Test("a first card that is not ASCII is still not a FITS file", .scratchDirectory)
  func testFITSFile_read_firstCardStaysStrict() throws {
    let url = try Self.write(
      Self.header(cards: [], replacing: []).replacingBytes(at: 0, with: 0xB0), named: "x.fit")
    #expect(throws: FITSFileError(path: url.path, reason: .nonASCIIHeader)) {
      try FITSFile.read(at: url)
    }
  }

  @Test("an error reads as a sentence naming the file, never as a Swift dump")
  func testFITSFileError_description() {
    let error = FITSFileError(path: "/captures/B/b_1.fit", reason: .nonASCIIHeader)
    #expect("\(error)" == "/captures/B/b_1.fit: not a FITS file (its header is not text)")
    #expect("\(FITSError.truncatedData)" == "the image data is shorter than its header says")
    #expect("\(FITSError.missingCard("NAXIS1"))" == "the header has no valid NAXIS1 card")
  }
}

extension Data {
  fileprivate func replacingBytes(at index: Int, with byte: UInt8) -> Data {
    var copy = self
    copy[copy.startIndex + index] = byte
    return copy
  }
}
