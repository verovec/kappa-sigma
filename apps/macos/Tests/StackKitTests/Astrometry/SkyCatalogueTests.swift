import Foundation
import StackKit
import Testing

/// The sky-object catalogue (card 0129), a port of the legacy `internal/skycat`: one normalised
/// name key, Siril's five lists merged Messier first, a ranked search over names, common names
/// and aliases, and the OpenNGC overlay for types and common names.
@Suite("SkyCatalogue — Siril's lists, merged, searchable by any alias")
struct SkyCatalogueTests {
  @Test(
    "normalize: upper-case, A–Z and 0–9 only (legacy skycat.normalize)",
    arguments: [
      ("sh2-132", "SH2132"), ("Sh 2-132", "SH2132"), ("SH2132", "SH2132"), ("m 31", "M31"),
      ("NGC 224", "NGC224"), ("m-101", "M101"), ("Andromeda galaxy", "ANDROMEDAGALAXY"),
      ("  ", ""), ("Hα", "H"),
    ])
  func testNormalizeTable(_ name: String, _ key: String) {
    #expect(SkyCatalogue.normalize(name) == key)
  }

  /// Legacy `searchFixture`: records built in memory, common names pinned by hand.
  static let searchFixture = SkyCatalogue(objects: [
    SkyObject(
      name: "M31", raDeg: 10.68, decDeg: 41.27, source: .messier, magnitude: 3.4,
      aliases: ["NGC224"], commonNames: ["Andromeda Galaxy"]),
    SkyObject(
      name: "M110", raDeg: 10.09, decDeg: 41.68, source: .messier, magnitude: 8.1,
      aliases: ["NGC205"]),
    SkyObject(
      name: "NGC7000", raDeg: 314.75, decDeg: 44.31, source: .ngc, magnitude: 4,
      commonNames: ["North America Nebula"]),
    SkyObject(name: "NGC7008", raDeg: 316.0, decDeg: 54.5, source: .ngc),
    SkyObject(
      name: "IC5070", raDeg: 313.9, decDeg: 44.36, source: .ic, commonNames: ["Pelican Nebula"]),
    SkyObject(name: "Sh2-131", raDeg: 315.4, decDeg: 57.5, source: .sh2),
  ])

  struct Query: Sendable, CustomTestStringConvertible {
    let name: String
    let query: String
    let limit: Int
    /// The whole result, in order; nil checks only the first hit.
    let names: [String]?
    var first: String?
    var testDescription: String { name }
  }

  @Test(
    "search ranks exact before prefix before contains (legacy search_test.go)",
    arguments: [
      Query(
        name: "exact primary name outranks substring hits", query: "M31", limit: 5, names: nil,
        first: "M31"),
      Query(
        name: "punctuation and case are ignored", query: "m 31", limit: 5, names: nil,
        first: "M31"),
      Query(name: "alias resolves to the merged record", query: "ngc224", limit: 5, names: ["M31"]),
      Query(name: "common name is searchable", query: "andromeda", limit: 5, names: ["M31"]),
      Query(
        name: "multi-word common name matches without spaces", query: "north america", limit: 5,
        names: ["NGC7000"]),
      Query(
        name: "prefix match on a unique designation", query: "IC50", limit: 5, names: ["IC5070"]),
      Query(
        name: "shared prefix returns both, catalogue order breaks the tie", query: "NGC70",
        limit: 5, names: ["NGC7000", "NGC7008"]),
      Query(name: "no match yields nothing", query: "zzzz", limit: 5, names: []),
      Query(name: "blank query yields nothing", query: "   ", limit: 5, names: []),
      Query(name: "limit caps the result set", query: "NGC70", limit: 1, names: ["NGC7000"]),
      Query(name: "zero limit yields nothing", query: "M31", limit: 0, names: []),
    ])
  func testSearchRankingTable(_ query: Query) throws {
    let names = Self.searchFixture.search(query.query, limit: query.limit).map(\.name)
    if let expected = query.names {
      #expect(names == expected)
    } else {
      let first = try #require(names.first)
      #expect(first == query.first)
    }
  }

  @Test("an equal rank breaks toward Messier, then NGC, then IC — even a fainter Messier row")
  func testSearchTieBreaksOnCatalogue() {
    let catalogue = SkyCatalogue(objects: [
      SkyObject(
        name: "NGC1976", raDeg: 0, decDeg: 0, source: .ngc, magnitude: 4,
        commonNames: ["Orion Nebula"]),
      SkyObject(
        name: "M42x", raDeg: 0, decDeg: 0, source: .messier, magnitude: 9,
        commonNames: ["Orion Nebula"]),
      SkyObject(name: "IC434", raDeg: 0, decDeg: 0, source: .ic, commonNames: ["Orion Nebula"]),
    ])
    #expect(catalogue.search("orion nebula", limit: 5).map(\.name) == ["M42x", "NGC1976", "IC434"])
  }

  @Test("within a catalogue, a known magnitude sorts ahead of an unknown one")
  func testSearchPrefersPhotometry() {
    let catalogue = SkyCatalogue(objects: [
      SkyObject(name: "NGC6960", raDeg: 0, decDeg: 0, source: .ngc),
      SkyObject(name: "NGC6992", raDeg: 0, decDeg: 0, source: .ngc, magnitude: 7),
    ])
    #expect(catalogue.search("NGC69", limit: 5).map(\.name) == ["NGC6992", "NGC6960"])
  }

  static func fixtures() throws -> URL {
    try #require(
      Bundle.module.url(forResource: "catalogue", withExtension: nil, subdirectory: "Fixtures"))
  }

  @Test("load merges the five lists Messier first: M1 = NGC1952 = Sh2-244 is one object, M1")
  func testLoadMergesSourcesMessierFirst() throws {
    let catalogue = try SkyCatalogue.load(folder: try Self.fixtures(), overlay: nil)
    // M1, M31, NGC6946, NGC7000, IC1, IC2, Sh2-1, Sh2-132, LdN-1.
    #expect(catalogue.objects.count == 9)
    #expect(!catalogue.objects.contains { ["NGC1952", "Sh2-244", "NGC224"].contains($0.name) })
    let crab = try #require(catalogue.object(named: "ngc 1952"))
    #expect(crab.name == "M1" && crab.source == .messier)
    #expect(crab.magnitude == 8.4, "Messier's photometry, not NGC's 8.9")
    #expect(catalogue.object(named: "Sh2-244")?.name == "M1")
    #expect(catalogue.object(named: "North America Nebula")?.name == "NGC7000")
    let ic1 = try #require(catalogue.object(named: "IC1"))
    #expect(ic1.magnitude == nil && ic1.majorAxisArcmin == nil, "empty cells are unknown, not 0")
    #expect(catalogue.object(named: "LdN-1")?.source == .ldn)
    let sh2 = try #require(catalogue.object(named: "sh2-132"))
    #expect(sh2.raDeg == 334.698615 && sh2.decDeg == 56.134831 && sh2.magnitude == nil)
  }

  @Test("an empty folder loads an empty catalogue; a list without name/ra/dec is refused")
  func testLoadEmptyAndMalformed() throws {
    let empty = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: empty) }
    #expect(try SkyCatalogue.load(folder: empty, overlay: nil).objects.isEmpty)
    try "name,dec\nM1,22\n".write(
      to: empty.appendingPathComponent("messier.csv"), atomically: true, encoding: .utf8)
    #expect(throws: SkyCatalogueError.self) { try SkyCatalogue.load(folder: empty, overlay: nil) }
  }

  @Test(
    "the OpenNGC overlay adds types, ellipses and common names, a Messier row via its NGC alias",
    arguments: [
      ("NGC6946", "G", "Fireworks Galaxy"), ("M31", "G", "Andromeda Galaxy"),
      ("NGC7000", "HII", "North America Nebula"), ("M1", "SNR", "Crab Nebula"),
    ])
  func testOpenNGCOverlayTypesAndCommonNames(_ name: String, _ type: String, _ common: String)
    throws
  {
    let folder = try Self.fixtures()
    let catalogue = try SkyCatalogue.load(
      folder: folder, overlay: folder.appendingPathComponent("openngc.csv"))
    let object = try #require(catalogue.object(named: name))
    #expect(object.type == type && object.commonNames.contains(common))
    let fireworks = try #require(catalogue.object(named: "NGC6946"))
    #expect(fireworks.majorAxisArcmin == 11.40 && fireworks.minorAxisArcmin == 10.84)
    #expect(fireworks.surfaceBrightness == 23.73 && fireworks.morphology == "SABc")
    #expect(catalogue.search("fireworks", limit: 3).map(\.name) == ["NGC6946"])
  }

  @Test("an overlay row without a name or a type gives nothing")
  func testOpenNGCSkipsBadRows() throws {
    let folder = try Self.fixtures()
    let entries = try SkyCatalogue.overlayEntries(
      contentsOf: folder.appendingPathComponent("openngc-bad-rows.csv"))
    #expect(Array(entries.keys) == ["NGC1"])
    #expect(entries["NGC1"]?.type == "G" && entries["NGC1"]?.commonNames == ["Alpha"])
  }

  @Test("the committed OpenNGC overlay loads from StackKit's resources and types M31")
  func testCommittedOverlay() throws {
    let url = try #require(SkyCatalogue.openNGCOverlay)
    let entries = try SkyCatalogue.overlayEntries(contentsOf: url)
    #expect(entries.count > 10_000)
    #expect(entries["NGC224"]?.commonNames == ["Andromeda Galaxy"])
  }

  @Test(
    "Siril's catalogue folder from the siril-cli path: the app bundle, or beside a prefix's share",
    arguments: [
      (
        "/Applications/Siril.app/Contents/MacOS/siril-cli",
        "/Applications/Siril.app/Contents/Resources/share/siril/catalogue"
      ),
      (
        "/Users/me/Apps/Siril.app/Contents/MacOS/siril",
        "/Users/me/Apps/Siril.app/Contents/Resources/share/siril/catalogue"
      ),
      ("/opt/homebrew/bin/siril-cli", "/opt/homebrew/share/siril/catalogue"),
      ("/usr/local/siril/bin/siril-cli", "/usr/local/siril/share/siril/catalogue"),
    ])
  func testFolderFromSirilPath(_ binary: String, _ folder: String) {
    #expect(SkyCatalogue.folder(sirilPath: binary).path == folder)
  }

  @Test("SIRIL_BIN names the binary the folder is derived from; no Siril there is sirilMissing")
  func testInstalledHonoursSirilBin() {
    let environment = ["SIRIL_BIN": "/nonexistent/prefix/bin/siril-cli"]
    #expect(throws: SkyCatalogueError.sirilMissing(path: "/nonexistent/prefix/bin/siril-cli")) {
      try SkyCatalogue.installed(environment: environment)
    }
  }
}
