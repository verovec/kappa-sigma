import Foundation
import StringCatalog
import TestSupport
import Testing

/// The compiler the build plugin runs: tables Foundation resolves, in both languages.
@Suite("CatalogCompiler — xcstrings to .lproj tables Foundation reads")
struct CatalogCompilerTests {
  @Test("compiled tables resolve plain, escaped and plural keys in fr and en", .scratchDirectory)
  func testCompiledTablesResolve() throws {
    let folder = try ScratchDirectory.url
    try CatalogCompiler.compile(try Catalogs.fixture("valid"), into: folder)
    let french = try #require(Bundle(url: folder.appendingPathComponent("fr.lproj")))
    let english = try #require(Bundle(url: folder.appendingPathComponent("en.lproj")))

    #expect(String(localized: "Night of \("2026-09-22")", bundle: french) == "Nuit du 2026-09-22")
    #expect(String(localized: "Night of \("2026-09-22")", bundle: english) == "Night of 2026-09-22")
    let one = 1
    let many = 36
    #expect(
      String(localized: "build from \(one) frames", bundle: french) == "construire depuis 1 brute")
    #expect(
      String(localized: "build from \(many) frames", bundle: french)
        == "construire depuis 36 brutes")
    #expect(String(localized: "build from \(one) frames", bundle: english) == "build from 1 frame")
    #expect(
      String(localized: "Say \"hi\"\n\(many)% done", bundle: french) == "Dites « salut »\n36 % fait"
    )
  }

  @Test("a catalog failing the gate is not compiled", .scratchDirectory)
  func testGateFailsTheBuild() throws {
    let folder = try ScratchDirectory.url
    #expect(throws: CatalogCompiler.Failure.self) {
      try CatalogCompiler.compile(try Catalogs.fixture("missing-fr"), into: folder)
    }
    #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("fr.lproj").path))
  }

  @Test("tables are sorted and stable")
  func testTablesAreDeterministic() throws {
    let catalog = try Catalogs.fixture("valid")
    let first = try CatalogCompiler.tables(of: catalog, language: "fr")
    #expect(try CatalogCompiler.tables(of: catalog, language: "fr") == first)
    #expect(
      first.strings
        == "\"Night of %@\" = \"Nuit du %@\";\n"
        + "\"Say \\\"hi\\\"\\n%lld%% done\" = \"Dites « salut »\\n%lld %% fait\";\n")
  }
}
