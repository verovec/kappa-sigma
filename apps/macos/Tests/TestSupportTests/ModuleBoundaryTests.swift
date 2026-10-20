import Foundation
import TestSupport
import Testing

@Suite("ModuleBoundary flags dependencies and imports outside the allow-list")
struct ModuleBoundaryTests {
  static let rules = BoundaryRules(
    allowedDependencies: [
      "ImageKit": [],
      "ProjectKit": ["GRDB"],
      "HelpKit": [],
      "AstroStackApp": ["ImageKit", "ProjectKit"],
    ],
    uiModules: ["AstroStackApp"]
  )

  struct Case: Sendable, CustomTestStringConvertible {
    let module: String
    let sources: [String: String]
    let expected: [String]
    var testDescription: String { "\(module): \(expected.count) violation(s)" }
  }

  static let cases: [Case] = [
    Case(module: "ImageKit", sources: ["A.swift": "import Foundation\n"], expected: []),
    Case(
      module: "ProjectKit", sources: [:], expected: ["ProjectKit depends on ImageKit (not allowed)"]
    ),
    Case(
      module: "HelpKit", sources: [:],
      expected: ["HelpKit depends on AstroStackApp", "HelpKit has no test target"]),
    Case(
      module: "Orphan", sources: [:],
      expected: ["Orphan has no allow-list entry", "Orphan has no test target"]),
    Case(module: "Missing", sources: [:], expected: ["Missing is not declared in Package.swift"]),
    Case(
      module: "ImageKit",
      sources: [
        "View.swift": "internal import Foundation\n@preconcurrency public import SwiftUI\n",
        "Win.swift": "\n\nimport AppKit\n",
        "Ok.swift": "// import SwiftUI in a comment is fine\nlet s = \"import AppKit\"\n",
      ],
      expected: [
        "ImageKit imports SwiftUI (View.swift:2)", "ImageKit imports AppKit (Win.swift:3)",
      ]),
    Case(
      module: "AstroStackApp", sources: ["App.swift": "import SwiftUI\nimport AppKit\n"],
      expected: ["AstroStackApp has no test target"]),
  ]

  @Test("violations for a module against the fixture manifest", arguments: cases)
  func testModuleBoundary_violations(_ testCase: Case) throws {
    let targets = ManifestParser.targets(in: try ManifestParserTests.fixture())
    let found = ModuleBoundary.violations(
      module: testCase.module, targets: targets, sources: testCase.sources, rules: Self.rules)
    #expect(found.map(\.description) == testCase.expected)
  }

  @Test("the real manifest of this package is found from a test file")
  func testModuleBoundary_locatesPackageRoot() throws {
    let root = try ModuleBoundary.packageRoot(from: #filePath)
    #expect(FileManager.default.fileExists(atPath: root + "/Package.swift"))
    #expect(root.hasSuffix("apps/macos"))
  }
}
