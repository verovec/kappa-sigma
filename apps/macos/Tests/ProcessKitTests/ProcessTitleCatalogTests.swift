import Foundation
import ProcessKit
import StringCatalog
import TestSupport
import Testing

/// ProcessKit's catalog holds exactly the titles a panel shows: every registered process, its
/// parameters and the palettes, in fr and en.
@Suite("ProcessKit catalog — process, parameter and palette titles in fr and en")
struct ProcessTitleCatalogTests {
  static func catalog() throws -> StringCatalog {
    let root = try ModuleBoundary.packageRoot(from: #filePath)
    return try StringCatalog(
      contentsOf: URL(fileURLWithPath: root + "/Sources/ProcessKit/Localizable.xcstrings"))
  }

  /// Every title the registry and the palettes declare.
  static func titles() throws -> Set<String> {
    let types = try ProcessRegistry.standard().types
    return Set(
      types.map { $0.title } + types.flatMap { $0.schema.specs.map(\.title) }
        + types.flatMap { $0.suggestionReasons } + Palette.allCases.map(\.title))
  }

  @Test("every title is a key, and every key is a title (none stale)")
  func testCatalogMatchesTheRegistry() throws {
    let titles = try Self.titles()
    #expect(Set(try Self.catalog().strings.keys) == titles)
    #expect(CatalogAudit.violations(of: try Self.catalog(), used: titles) == [])
  }

  @Test("titles resolve in each language")
  func testTitlesResolve() {
    var french = ProcessKitResources.title(ChannelCombinationProcess.title)
    french.locale = Locale(identifier: "fr")
    #expect(String(localized: french) == "Combinaison de canaux")
    let english = ProcessKitResources.title("Red weight", locale: Locale(identifier: "en"))
    #expect(String(localized: english) == "Red weight")
  }
}
