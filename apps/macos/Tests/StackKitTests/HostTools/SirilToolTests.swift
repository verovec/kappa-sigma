import Foundation
import StackKit
import TestSupport
import Testing

@Suite("SirilTool: Siril speaks English to the app, whatever the Mac's language (card 0124)")
struct SirilToolTests {
  @Test("the locale set over the app's environment is English, every locale key")
  func testSirilTool_englishLocale() {
    #expect(
      SirilTool.englishLocale == [
        "LANG": "en_US.UTF-8", "LANGUAGE": "en", "LC_ALL": "en_US.UTF-8",
        "LC_MESSAGES": "en_US.UTF-8",
      ])
  }

  @Test(
    "the app's own settings ask for English: Siril's setting outranks the environment",
    .scratchDirectory)
  func testSirilAppSettings_write_english() throws {
    let file = try ScratchDirectory.url.appendingPathComponent("siril.ini")
    try SirilAppSettings.write(to: file, catalogues: URL(fileURLWithPath: "/catalogues"))
    let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
    let core = try #require(lines.firstIndex(of: "[core]"))
    let next = lines[(core + 1)...].firstIndex { $0.hasPrefix("[") } ?? lines.endIndex
    #expect(lines[(core + 1)..<next].contains("lang=en_US"))
  }
}
