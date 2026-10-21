import Foundation
import TestSupport
import Testing

extension InfoPlistTests {
  @Test("the Documents-access prompt says what is read, read-only, in English and French")
  func testDocumentsUsageDescription() throws {
    let english = try #require(Self.plist()["NSDocumentsFolderUsageDescription"] as? String)
    #expect(english.contains("Documents/astro") && english.contains("read-only"))

    let root = try ModuleBoundary.packageRoot(from: #filePath)
    let url = URL(fileURLWithPath: root + "/App/fr.lproj/InfoPlist.strings")
    let strings = try #require(
      PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        as? [String: String])
    let french = try #require(strings["NSDocumentsFolderUsageDescription"])
    #expect(french.contains("Documents/astro") && french.contains("lecture seule"))

    // The bundle script copies the localisations next to the executable's resources.
    let script = try String(
      contentsOf: URL(fileURLWithPath: root + "/../../scripts/app-bundle.sh"), encoding: .utf8)
    #expect(script.contains("cp -R App/*.lproj \"$app/Contents/Resources/\""))
  }
}
