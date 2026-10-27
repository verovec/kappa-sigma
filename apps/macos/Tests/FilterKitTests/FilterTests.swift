import FilterKit
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
      ("DUALBAND", .dualband), ("dualband-sii", .dualbandSII), ("Multiband", .multiband),
    ])
  func testFilterSet_parse(raw: String, expected: FilterSet) throws {
    #expect(try FilterSet(parsing: raw) == expected)
  }

  @Test("an unknown filter set is an error, and only measured sets are known")
  func testFilterSet_known() {
    #expect(throws: FilterSet.ParseError.unknownFilterSet("uhc")) { try FilterSet(parsing: "uhc") }
    #expect(FilterSet.allCases == [.unknown, .broadband, .dualband, .dualbandSII, .multiband])
    #expect(
      FilterSet.allCases.filter(\.isKnown) == [.broadband, .dualband, .dualbandSII, .multiband])
    #expect(FilterSet.allCases.map(\.rawValue).contains("dualband"), "the wire value stays")
  }

  @Test(
    "a line's continuum references and colour plane",
    arguments: [
      (Filter.hydrogenAlpha, [Filter.red, .luminance], 0),
      (.oxygenIII, [.green, .blue, .luminance], 1),
      (.sulfurII, [.red, .luminance], 0),
    ])
  func testLine_continuum(filter: Filter, filters: [Filter], plane: Int) throws {
    let line = try #require(filter.line)
    #expect(line.continuumFilters == filters)
    #expect(line.colourPlane == plane)
  }

  @Test(
    "a line's rest wavelength and panel name",
    arguments: [
      (Filter.hydrogenAlpha, 656.3, "Hα"), (.oxygenIII, 500.7, "[OIII]"),
      (.sulfurII, 671.6, "[SII]"),
    ])
  func testLine_wavelengthAndName(filter: Filter, nm: Double, name: String) throws {
    let line = try #require(filter.line)
    #expect(line.wavelengthNm == nm)
    #expect(line.displayName == name)
  }

  @Test("broadband filters have no line; the two lists split the catalogue in order")
  func testLine_broadbandHasNone() {
    for filter in [Filter.luminance, .red, .green, .blue] { #expect(filter.line == nil) }
    #expect(Filter.narrowband == [.hydrogenAlpha, .oxygenIII, .sulfurII])
    #expect(Filter.broadband == [.luminance, .red, .green, .blue])
    #expect(Set(Filter.narrowband + Filter.broadband) == Set(Filter.allCases))
  }

  @Test(
    "a clip filter's planes carry one line each, or none",
    arguments: [
      (FilterSet.unknown, nil, nil), (.broadband, nil, nil),
      (.dualband, Filter.hydrogenAlpha, Filter.oxygenIII), (.dualbandSII, .sulfurII, .oxygenIII),
      (.multiband, .hydrogenAlpha, .oxygenIII),
    ])
  func testFilterSet_lines(set: FilterSet, red: Filter?, greenBlue: Filter?) {
    #expect(set.lines?.red == red)
    #expect(set.lines?.greenBlue == greenBlue)
  }

  @Test("only the multi-band clip mixes a second line into each plane")
  func testFilterSet_mixed() {
    #expect(FilterSet.allCases.filter(\.mixesLines) == [.multiband])
  }
}
