import StringCatalog
import TestSupport
import Testing

/// The localisation gate over the three shipped catalogs, and the fixtures that prove it fails.
@Suite("Localisation coverage — every shipped key in fr and en, same specifiers, none stale")
struct LocalisationCoverageTests {
  struct Rejected: Sendable, CustomTestStringConvertible {
    let fixture: String
    let violation: CatalogViolation
    var testDescription: String { fixture }
  }

  nonisolated static let rejected: [Rejected] = [
    Rejected(fixture: "missing-fr", violation: .missing(key: "Cancel", language: "fr")),
    Rejected(fixture: "untranslated-fr", violation: .untranslated(key: "Cancel", language: "fr")),
    Rejected(
      fixture: "format-mismatch",
      violation: .formatMismatch(
        key: "Night of %@", language: "fr", expected: ["%@"], found: ["%lld"])),
    Rejected(
      fixture: "device-variation",
      violation: .unsupported(key: "Open", language: "fr", reason: "device variations")),
    Rejected(fixture: "empty-variations", violation: .missing(key: "Open", language: "fr")),
  ]

  @Test("every key of the catalog has a translated fr and en value", arguments: Catalogs.targets)
  func testEveryKeyHasFrAndEn(_ target: String) throws {
    let catalog = try Catalogs.shipped(target)
    #expect(!catalog.strings.isEmpty, "\(target) ships an empty catalog")
    let violations = CatalogAudit.violations(of: catalog).filter {
      switch $0 {
      case .missing, .untranslated, .sourceLanguage: true
      default: false
      }
    }
    #expect(violations == [])
  }

  @Test("fr and en read the same arguments as the key", arguments: Catalogs.targets)
  func testFormatSpecifiersMatchAcrossLanguages(_ target: String) throws {
    let violations = CatalogAudit.violations(of: try Catalogs.shipped(target)).filter {
      switch $0 {
      case .formatMismatch, .unsupported: true
      default: false
      }
    }
    #expect(violations == [])
  }

  /// ProcessKit composes its titles (`"Red" + " weight"`): ProcessKitTests checks them against
  /// the registry instead.
  @Test("no key outlives the literal that used it", arguments: ["AstroStackApp", "RenderKit"])
  func testNoStaleKey(_ target: String) throws {
    let used = CatalogAudit.usedShapes(in: try Catalogs.sources(target))
    let stale = CatalogAudit.violations(of: try Catalogs.shipped(target), used: used).filter {
      if case .stale = $0 { true } else { false }
    }
    #expect(stale == [])
  }

  @Test("the build plugin declares the outputs of every language the compiler writes")
  func testPluginLanguagesMatchTheCatalog() throws {
    let root = try ModuleBoundary.packageRoot(from: #filePath)
    let plugin = try String(
      contentsOfFile: root + "/Plugins/CatalogPlugin/CatalogPlugin.swift", encoding: .utf8)
    let list = StringCatalog.languages.map { "\"\($0)\"" }.joined(separator: ", ")
    #expect(plugin.contains("private static let languages = [\(list)]"))
  }

  @Test("the gate rejects a broken catalog", arguments: rejected)
  func testGateRejectsFixture(_ row: Rejected) throws {
    #expect(CatalogAudit.violations(of: try Catalogs.fixture(row.fixture)) == [row.violation])
  }

  @Test("a valid catalog passes, and a key no source uses is stale")
  func testValidCatalogAndStaleKey() throws {
    let catalog = try Catalogs.fixture("valid")
    #expect(CatalogAudit.violations(of: catalog) == [])
    let used = CatalogAudit.usedShapes(in: [
      #"Text("Night of \(night.session)")"#, #"String(localized: "build from \(count) frames")"#,
    ])
    #expect(
      CatalogAudit.violations(of: catalog, used: used) == [
        .stale(key: "Say \"hi\"\n%lld%% done")
      ])
  }
}
