import StackKit
import Testing

/// Translated from `internal/filters/filters_test.go` — the ONE canonical filter list (CLAUDE.md).
@Suite("Filter — the one canonical list, its aliases and order")
struct FilterTests {
  @Test("the list is exactly L, R, G, B, Ha, OIII, SII in display order")
  func testCanonicalListAndAliases_list() {
    #expect(Filter.allCases.map(\.rawValue) == ["L", "R", "G", "B", "Ha", "OIII", "SII"])
    #expect(Filter.allCases.count == 7)
  }

  @Test(
    "aliases canonicalize to a filter token",
    arguments: [
      ("Luminance", "L"), ("clear", "L"), ("RED", "R"), ("V", "G"), (" blue ", "B"), ("Ha", "Ha"),
      ("H-alpha", "Ha"), ("h_alpha", "Ha"), ("oiii", "OIII"), ("O3", "OIII"), ("O-III", "OIII"),
      ("oxygen", "OIII"), ("sii", "SII"), ("S2", "SII"), ("S-II", "SII"), ("sulfur", "SII"),
      ("SULPHUR", "SII"),
    ])
  func testCanonicalListAndAliases_token(raw: String, expected: String) {
    #expect(Filter.token(raw)?.rawValue == expected)
  }

  @Test("a non-filter is not a token", arguments: ["Baader", "", "RGB"])
  func testFilter_token_unknown(raw: String) {
    #expect(Filter.token(raw) == nil)
  }

  @Test(
    "normalize abbreviates known names and keeps unknown ones verbatim",
    arguments: [(" s2 ", "SII"), ("  Baader UHC  ", "Baader UHC"), ("   ", "")])
  func testFilter_normalize(raw: String, expected: String) {
    #expect(Filter.normalize(raw) == expected)
  }

  @Test("only the emission lines are narrowband")
  func testFilter_isNarrowband() {
    for name in ["Ha", "OIII", "SII"] { #expect(Filter.isNarrowband(name), "\(name)") }
    for name in ["L", "R", "G", "B", "", "Baader"] { #expect(!Filter.isNarrowband(name)) }
  }

  @Test("rank follows the canonical order, unknown filters after")
  func testFilter_rank() {
    #expect(Filter.rank("L") == 0)
    #expect(Filter.rank("Ha") == 4)
    #expect(Filter.rank("SII") == 6)
    #expect(Filter.rank("Baader") == 7)
  }

  @Test("sorting is canonical, then alphabetical")
  func testFilter_less() {
    let sorted = ["SII", "zeta", "B", "Ha", "alpha", "L", "OIII", "R", "G"].sorted(by: Filter.less)
    #expect(sorted == ["L", "R", "G", "B", "Ha", "OIII", "SII", "alpha", "zeta"])
  }

  @Test(
    "colour aliases are not mono; empty is neither; a custom name is mono",
    arguments: [
      ("RGB", true, false), ("rgb", true, false), ("OSC", true, false), ("Color", true, false),
      ("colour", true, false), ("Bayer", true, false), ("", false, false), ("  ", false, false),
      ("L", false, true), ("Ha", false, true), ("Custom", false, true),
    ])
  func testFilter_isColorAndIsMono(raw: String, color: Bool, mono: Bool) {
    #expect(Filter.isColor(raw) == color)
    #expect(Filter.isMono(raw) == mono)
  }

  @Test("the one-shot-colour channel name is not a wheel filter")
  func testFilter_colorIsNotCanonical() {
    #expect(Filter.color == "RGB")
    #expect(Filter.rank(Filter.color) == Filter.allCases.count)
    #expect(!Filter.isNarrowband(Filter.color))
    #expect(Filter.token(Filter.color) == nil)
  }

  @Test(
    "a filter set parses from its wire value; empty is unknown",
    arguments: [
      ("", FilterSet.unknown), ("unknown", .unknown), (" Broadband ", .broadband),
      ("DUALBAND", .dualband),
    ])
  func testFilterSet_parse(raw: String, expected: FilterSet) throws {
    #expect(try FilterSet(parsing: raw) == expected)
  }

  @Test("an unknown filter set is an error, and only measured sets are known")
  func testFilterSet_known() {
    #expect(throws: InspectError.self) { try FilterSet(parsing: "uhc") }
    #expect(FilterSet.allCases == [.unknown, .broadband, .dualband])
    #expect(FilterSet.allCases.filter(\.isKnown) == [.broadband, .dualband])
  }
}
