import ImageKit
import Testing

/// Card 0106: one list says what a plate-solution card is, primary or alternate, for every
/// reader (`isWCS`, `droppingWCS`, `moved(by:)`).
@Suite("FITS header: which cards are a plate solution")
struct FITSHeaderWCSTests {
  static let cases: [(keyword: String, kind: SolutionKeyword?)] = [
    // The primary solution: axes, matrix, frame, solver flag, SIP (0093's list).
    ("CTYPE1", .primary), ("CUNIT2", .primary), ("CRPIX1", .primary), ("CRVAL2", .primary),
    ("CDELT1", .primary), ("CROTA2", .primary), ("CD1_1", .primary), ("PC2_1", .primary),
    ("A_ORDER", .primary), ("BP_ORDER", .primary), ("A_2_0", .primary), ("BP_0_3", .primary),
    ("LONPOLE", .primary), ("LATPOLE", .primary), ("EQUINOX", .primary), ("RADESYS", .primary),
    ("PLTSOLVD", .primary),
    // … and the wider set 0090 also removed: any axis, PV/PS, CNAME/CRDER/CSYER, names.
    ("CTYPE3", .primary), ("CD3_3", .primary), ("PV1_1", .primary), ("PS2_0", .primary),
    ("CNAME1", .primary), ("CRDER2", .primary), ("CSYER1", .primary), ("WCSAXES", .primary),
    ("WCSNAME", .primary), ("RADECSYS", .primary),
    // An alternate solution: a primary keyword and a letter (FITS WCS paper I §3.5).
    ("CTYPE1A", .alternate), ("CRPIX2B", .alternate), ("CD1_1A", .alternate),
    ("PV1_1Z", .alternate), ("WCSAXESA", .alternate), ("WCSNAMEA", .alternate),
    ("RADESYSB", .alternate), ("EQUINOXA", .alternate),
    // Not a solution.
    ("OBJECT", nil), ("CDFORM", nil), ("FILTERA", nil), ("FOCALLEN", nil), ("EXPTIME", nil),
    ("CD1", nil), ("PC1_X", nil), ("A_ORDERA", nil), ("PLTSOLVDA", nil), ("CTYPE", nil),
    // An index is ASCII digits, no sign; a doubtful form (leading zero, index 0) is dropped.
    ("CRPIX+1", nil), ("A_-1_2", nil), ("PC1_+2", nil), ("CRPIX+1A", nil), ("CD1_-1A", nil),
    ("CRPIX1\u{0301}", nil), ("CRPIX01", .primary), ("CTYPE0", .primary), ("PC1_0", .primary),
    ("PV2_0", .primary), ("A_02_0", .primary), ("CRPIX10", .primary), ("CD1_2A", .alternate),
  ]

  @Test("testSolutionKeywords", arguments: cases)
  func testSolutionKeywords(keyword: String, kind: SolutionKeyword?) {
    #expect(FITSHeader.solutionKeyword(keyword) == kind, "\(keyword)")
    #expect(FITSHeader.isWCS(keyword) == (kind == .primary), "\(keyword)")
  }
}
