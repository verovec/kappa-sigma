import AstroStackApp
import Foundation
import Testing

@Suite("AstroFormat — disk sizes")
struct AstroFormatBytesTests {
  @Test(
    "a size on disk reads in decimal units, in the user's language",
    arguments: [
      (Int64(74_000_000_000), "74 Go", "74 GB"),
      (Int64(1_250_000_000), "1,25 Go", "1.25 GB"),
      (Int64(4096), "4 ko", "4 kB"),
    ])
  func testBytes(_ bytes: Int64, french: String, english: String) {
    #expect(AstroFormatTests.plain(AstroFormatTests.french.bytes(bytes)) == french)
    #expect(AstroFormatTests.plain(AstroFormatTests.english.bytes(bytes)) == english)
  }
}
