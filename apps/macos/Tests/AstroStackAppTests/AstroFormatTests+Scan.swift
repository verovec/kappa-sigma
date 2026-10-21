import AstroStackApp
import Foundation
import Testing

extension AstroFormatTests {
  @Test("a scan's count, grouped as each locale groups integers")
  func testFilesRead() {
    let (french, english) = (Self.french, Self.english)
    #expect(
      french.filesRead(1_234, of: 3_480)
        == "\(french.integer(1_234)) / \(french.integer(3_480)) fichiers lus")
    #expect(english.filesRead(1_234, of: 3_480) == "1,234 / 3,480 files read")
  }
}
