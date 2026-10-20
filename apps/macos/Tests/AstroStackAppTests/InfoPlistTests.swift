import AstroStackApp
import Foundation
import ProjectKit
import TestSupport
import Testing

@Suite("App/Info.plist declares the document type the code implements")
struct InfoPlistTests {
  static func plist() throws -> [String: Any] {
    let root = try ModuleBoundary.packageRoot(from: #filePath)
    let data = try Data(contentsOf: URL(fileURLWithPath: root + "/App/Info.plist"))
    let object = try PropertyListSerialization.propertyList(from: data, format: nil)
    return try #require(object as? [String: Any])
  }

  @Test("the document type names ProjectDocument and the exported project type")
  func testInfoPlist_documentType() throws {
    let types = try #require(Self.plist()["CFBundleDocumentTypes"] as? [[String: Any]])
    let type = try #require(types.first)
    #expect(types.count == 1)
    #expect(type["LSItemContentTypes"] as? [String] == [ProjectPackage.typeIdentifier])
    #expect(type["LSTypeIsPackage"] as? Bool == true)
    let className = try #require(type["NSDocumentClass"] as? String)
    #expect(NSClassFromString(className) == ProjectDocument.self)
  }

  @Test("the exported type is a package with the .astrostack extension")
  func testInfoPlist_exportedType() throws {
    let exported = try #require(Self.plist()["UTExportedTypeDeclarations"] as? [[String: Any]])
    let type = try #require(exported.first)
    #expect(type["UTTypeIdentifier"] as? String == ProjectPackage.typeIdentifier)
    #expect((type["UTTypeConformsTo"] as? [String])?.contains("com.apple.package") == true)
    let tags = type["UTTypeTagSpecification"] as? [String: [String]]
    #expect(tags?["public.filename-extension"] == [ProjectPackage.fileExtension])
  }

  @Test("the bundle runs the executable the bundle script installs, on macOS 26")
  func testInfoPlist_bundle() throws {
    let plist = try Self.plist()
    #expect(plist["CFBundleExecutable"] as? String == "AstroStack")
    #expect(plist["LSMinimumSystemVersion"] as? String == "26.0")
    #expect(plist["CFBundlePackageType"] as? String == "APPL")
  }
}
