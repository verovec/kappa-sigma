import FilterKit
import Testing

/// Card 0163: the names capture programs write — a bandwidth, separators, a Greek letter,
/// brackets — reach the one catalogue through an exact canonicalisation pass; no edit distance,
/// no guess: anything the table does not hold is kept as written.
extension FilterTests {
  @Test(
    "testNormalize_TolerantNames: bandwidths, separators, Greek and brackets fall away",
    arguments: [
      ("H-alpha 7nm", "Ha"), ("Ha 3nm", "Ha"), ("Ha_3.5nm", "Ha"), ("OIII-6.5nm", "OIII"),
      ("OIII 6,5 nm", "OIII"), ("[OIII]", "OIII"), ("[S II]", "SII"), ("SII 6nm", "SII"),
      ("H-beta", "Hb"), ("Hβ", "Hb"), ("Hα", "Ha"), ("H alpha", "Ha"), ("Hydrogen Alpha", "Ha"),
      ("H.alpha", "Ha"), ("Lum", "L"), ("Luminance", "L"), ("Red", "R"), ("[NII] 3nm", "NII"),
      ("O III", "OIII"), ("S/II", "SII"),
      // Kept as written: no table hit after the pass.
      ("Filter 5", "Filter 5"), ("5", "5"), ("CLS", "CLS"), ("L-eXtreme", "L-eXtreme"),
      ("7nm", "7nm"), ("n2", "n2"), ("N 2", "N 2"), ("Baader", "Baader"),
    ])
  func testNormalize_TolerantNames(raw: String, expected: String) {
    #expect(Filter.normalize(raw) == expected)
  }

  @Test("testNormalize_ExactNamesUnchanged: every alias of the table maps as before")
  func testNormalize_ExactNamesUnchanged() {
    #expect(!Filter.aliases.isEmpty)
    for (alias, filter) in Filter.aliases {
      #expect(Filter.token(alias) == filter, "\(alias)")
      #expect(Filter.token(alias.uppercased()) == filter, "\(alias)")
      #expect(Filter.normalize(" \(alias) ") == filter.rawValue, "\(alias)")
    }
    // Every canonical token is its own alias.
    for filter in Filter.allCases {
      #expect(Filter.normalize(filter.rawValue) == filter.rawValue)
    }
  }
}
