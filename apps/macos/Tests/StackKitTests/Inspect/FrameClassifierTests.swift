import StackKit
import Testing

/// Translated from `internal/inspect/inspect_test.go` (IMAGETYP, stats) and
/// `classify_level_test.go` (the measured phone session).
@Suite("FrameClassifier — IMAGETYP, then the pixel curve")
struct FrameClassifierTests {
  // Measured on the 2026-08-11 phone session (classify_level_test.go).
  static let phoneBias = FrameStat(exposureMs: 67, brightFraction: 0.00052, peaks: 75)
  static let phoneDark = FrameStat(exposureMs: 10000, brightFraction: 0.00002, peaks: 2)
  static let horizonA = FrameStat(
    exposureMs: 10000, median: 0.28419, mad: 0.10755, brightFraction: 0.00125, peaks: 5)
  static let horizonB = FrameStat(
    exposureMs: 10000, median: 0.26863, mad: 0.11085, brightFraction: 0.00105, peaks: 4)
  static let horizonC = FrameStat(
    exposureMs: 10000, median: 0.28047, mad: 0.12101, brightFraction: 0.00047, peaks: 0)
  static let zenith = FrameStat(
    exposureMs: 10000, median: 0.26700, mad: 0.05439, brightFraction: 0.05286, peaks: 9)

  @Test(
    "IMAGETYP spellings of every capture program map to a type",
    arguments: [
      ("Light Frame", FrameType.light), ("LIGHT", .light), ("Dark", .dark), ("Dark Frame", .dark),
      ("Bias Frame", .bias), ("OFFSET", .bias), ("Flat Field", .flat), ("FlatDark", .darkFlat),
      ("Dark Flat", .darkFlat), ("weird", .unknown),
    ])
  func testFrameClassifier_imageType(value: String, expected: FrameType) {
    #expect(FrameClassifier.imageType(value) == expected)
  }

  @Test(
    "a session's curves resolve light, flat, bias and dark against each other",
    arguments: [
      (
        [
          FrameStat(exposureMs: 60000, median: 1200, mad: 40, peaks: 80),
          FrameStat(exposureMs: 1500, median: 30000, mad: 300),
          FrameStat(exposureMs: 0, median: 300, mad: 5),
          FrameStat(exposureMs: 60000, median: 500, mad: 50, peaks: 2),
        ], [FrameType.light, .flat, .bias, .dark]
      ),
      (
        [
          FrameStat(exposureMs: 120_000, median: 0.05, mad: 0.002, peaks: 60),
          FrameStat(exposureMs: 3000, median: 0.6, mad: 0.01),
          FrameStat(exposureMs: 0, median: 0.01, mad: 0.001),
          FrameStat(exposureMs: 120_000, median: 0.012, mad: 0.003, peaks: 1),
        ], [.light, .flat, .bias, .dark]
      ),
      (
        [
          FrameStat(exposureMs: 300_000, median: 900, mad: 30, brightFraction: 0.05, peaks: 3),
          FrameStat(exposureMs: 300_000, median: 800, mad: 60, brightFraction: 0.0002, peaks: 1),
        ], [.light, .dark]
      ),
      (
        [
          FrameStat(exposureMs: 0, measured: false),
          FrameStat(exposureMs: 60000, median: 1200, mad: 40, peaks: 80),
          FrameStat(exposureMs: 0, median: 300, mad: 5),
        ], [.light, .light, .bias]
      ),
      (
        [phoneBias, phoneDark, horizonA, horizonB, horizonC, zenith],
        [.bias, .dark, .light, .light, .light, .light]
      ),
    ])
  func testFrameClassifier_byStats(stats: [FrameStat], expected: [FrameType]) {
    #expect(FrameClassifier.byStats(stats) == expected)
  }

  @Test(
    "stars need a noise floor; a bright fraction does not",
    arguments: [
      (phoneBias, false),
      (FrameStat(exposureMs: 0, median: 0.0153, brightFraction: 0.11), true),
      (FrameStat(exposureMs: 0, median: 0.27, mad: 0.10, brightFraction: 0.002, peaks: 9), true),
      (FrameStat(exposureMs: 0, median: 0.27, mad: 0.10, brightFraction: 0.002, peaks: 4), false),
    ])
  func testFrameClassifier_hasStars(stat: FrameStat, expected: Bool) {
    #expect(FrameClassifier.hasStars(stat) == expected)
  }

  @Test("the exposed level is a quarter up from the darkest frame, only on a steep batch")
  func testFrameClassifier_exposedLevel() throws {
    let cut = try #require(
      FrameClassifier.exposedLevel([Self.phoneBias, Self.phoneDark, Self.horizonA, Self.zenith]))
    #expect(abs(cut - 0.0710) <= 0.001)
    let ordinary = [
      FrameStat(exposureMs: 0, median: 0.0153), FrameStat(exposureMs: 0, median: 0.0458),
    ]
    #expect(FrameClassifier.exposedLevel(ordinary) == nil)
    #expect(FrameClassifier.exposedLevel([FrameStat(exposureMs: 0, median: 0.5, measured: false)]) == nil)
  }

  @Test("an ordinary deep-sky batch keeps the old decision: a uniform dim frame is calibration")
  func testFrameClassifier_ordinarySessionUnchanged() {
    let types = FrameClassifier.byStats([
      FrameStat(exposureMs: 10, median: 0.0153, brightFraction: 0.11),
      FrameStat(exposureMs: 10, median: 0.0458),
    ])
    #expect(types[0] == .light)
    #expect(types[1].isCalibration)
  }
}
