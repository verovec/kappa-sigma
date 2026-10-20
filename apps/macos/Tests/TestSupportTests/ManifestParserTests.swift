import Foundation
import TestSupport
import Testing

@Suite("ManifestParser reads targets and dependencies from Package.swift")
struct ManifestParserTests {
  static func fixture() throws -> String {
    let url = try #require(
      Bundle.module.url(
        forResource: "boundary.Package.swift", withExtension: "txt", subdirectory: "Fixtures"))
    return try String(contentsOf: url, encoding: .utf8)
  }

  @Test("the fixture declares exactly its seven targets, comments ignored")
  func testManifestParser_targets_namesInOrder() throws {
    let targets = ManifestParser.targets(in: try Self.fixture())
    #expect(
      targets.map(\.name) == [
        "ImageKit", "ProjectKit", "HelpKit", "Orphan", "AstroStackApp", "ImageKitTests",
        "ProjectKitTests",
      ])
  }

  @Test(
    "dependencies: plain names, products and .target(name:) references",
    arguments: [
      ("ImageKit", DeclaredTarget.Kind.library, [String]()),
      ("ProjectKit", .library, ["GRDB", "ImageKit"]),
      ("HelpKit", .library, ["AstroStackApp"]),
      ("Orphan", .library, ["ImageKit"]),
      ("AstroStackApp", .executable, ["ImageKit", "ProjectKit"]),
      ("ImageKitTests", .test, ["ImageKit"]),
    ])
  func testManifestParser_targets_dependencies(
    name: String, kind: DeclaredTarget.Kind, dependencies: [String]
  ) throws {
    let targets = ManifestParser.targets(in: try Self.fixture())
    let target = try #require(targets.first { $0.name == name })
    #expect(target.kind == kind)
    #expect(target.dependencies == dependencies)
  }

  @Test("an empty or target-less manifest declares nothing")
  func testManifestParser_targets_emptyManifest() {
    #expect(ManifestParser.targets(in: "").isEmpty)
    #expect(ManifestParser.targets(in: "let package = Package(name: \"X\")").isEmpty)
  }
}
