import StackKit
import Testing

/// Translated from `internal/grade/seq_test.go`: the R lines are verbatim Siril 1.4.3 output.
@Suite("SirilSequence — per-frame registration data from a .seq file")
struct SirilSequenceTests {
  static let fixture = """
    S 'light_' 1 3 3 2 4 6 0 0 0
    I 1 1
    I 2 1
    I 3 0
    R0 7.28766 7.28766 0.971388 0 0.0131527 25 H 1.00001 -1.13159e-05 7.99992 \
    2.32884e-05 0.999998 -4.00171 8.49273e-08 -4.87644e-08 1
    R0 7.28553 7.28553 0.971923 0 0.0131605 25 H 1 0 0 0 1 0 0 0 1
    R0 0 0 0 0 0 0

    """

  @Test("non-finite metrics read as 0, the dropped-frame sentinel")
  func testSirilSequence_nonFinite() throws {
    let sequence = SirilSequence(
      parsing: "S 'light_' 1 2 2 2 4 6 0 0 0\nI 1 1\nI 2 1\n"
        + "R0 nan nan nan -1 inf 0 H nan nan nan nan nan nan nan nan nan\n"
        + "R0 7.28553 7.28553 0.971923 0 0.0131605 25 H 1 0 0 0 1 0 0 0 1\n")
    try #require(sequence.metrics.count == 2)
    let bad = sequence.metrics[0]
    #expect(bad.fwhm == 0 && bad.wfwhm == 0 && bad.background == 0)
    #expect(bad.homography == Array(repeating: 0, count: 9))
    #expect(bad.shiftX == 0 && bad.shiftY == 0)
    #expect(abs(sequence.metrics[1].fwhm - 7.28553) < 1e-9)
  }

  @Test("shifts come from the homography; the reference is identity; unregistered is zero")
  func testSirilSequence_shifts() throws {
    let sequence = SirilSequence(parsing: Self.fixture)
    try #require(sequence.metrics.count == 3)
    #expect(sequence.included == [true, true, false])
    #expect(abs(sequence.metrics[0].shiftX - 7.99992) < 1e-9)
    #expect(abs(sequence.metrics[0].shiftY + 4.00171) < 1e-9)
    #expect(abs(sequence.metrics[0].fwhm - 7.28766) < 1e-9)
    #expect(sequence.metrics[1].shiftX == 0 && sequence.metrics[1].shiftY == 0)
    #expect(sequence.metrics[2].fwhm == 0 && sequence.metrics[2].shiftX == 0)
  }

  @Test("the full homography and the S-line reference (0-based)")
  func testSirilSequence_homographyAndReference() {
    let sequence = SirilSequence(parsing: Self.fixture)
    #expect(sequence.reference == 4)
    #expect(sequence.metrics[0].hasHomography)
    #expect(abs(sequence.metrics[0].homography[0] - 1.00001) < 1e-9)
    #expect(abs(sequence.metrics[0].homography[8] - 1) < 1e-9)
    #expect(sequence.metrics[1].homography == [1, 0, 0, 0, 1, 0, 0, 0, 1])
    #expect(!sequence.metrics[2].hasHomography)
  }
}
