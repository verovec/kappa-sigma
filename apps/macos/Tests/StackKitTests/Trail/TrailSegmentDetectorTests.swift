import Foundation
import StackKit
import Testing

/// `TrailSegmentDetector` ports `trail.DetectSegments`: cases of `detect_test.go`, `fit_test.go`
/// and `trail_test.go` on 300 × 300 synthetic planes (the noise stream differs from Go's, the
/// behaviour asserted does not).
@Suite("TrailSegmentDetector — straight streaks localised as segments")
struct TrailSegmentDetectorTests {
  static let side = 300

  static func plane(background: Double = 0.1, sigma: Double = 0.004, seed: UInt64) -> [Float] {
    TrailSynth.noisyPlane(
      width: side, height: side, background: background, sigma: sigma, seed: seed)
  }

  static func detect(_ plane: [Float]) -> [TrailSegment] {
    TrailSegmentDetector.detect(plane, width: side, height: side, params: .residual(k: 5))
  }

  @Test("pure noise holds no trail")
  func testNoTrail() {
    #expect(Self.detect(Self.plane(sigma: 0.005, seed: 1)).isEmpty)
  }

  @Test("one 45° streak: one segment, orientation within 3°, spanning a quarter of the frame")
  func testSingleDiagonal() throws {
    var plane = Self.plane(seed: 2)
    TrailSynth.addStreak(
      &plane, width: Self.side, height: Self.side, from: (40, 40), to: (260, 260),
      amplitude: 0.1, sigma: 0.8)
    let segments = Self.detect(plane)
    let segment = try #require(segments.count == 1 ? segments.first : nil)
    #expect(abs(TrailSynth.angle(segment) - 45) <= 3)
    #expect(segment.t1 - segment.t0 > 0.25 * 300 && segment.width > 0)
  }

  @Test("two crossing streaks: two segments about 90° apart")
  func testTwoCrossing() throws {
    var plane = Self.plane(seed: 3)
    TrailSynth.addStreak(
      &plane, width: Self.side, height: Self.side, from: (40, 40), to: (260, 260),
      amplitude: 0.1, sigma: 0.8)
    TrailSynth.addStreak(
      &plane, width: Self.side, height: Self.side, from: (40, 260), to: (260, 40),
      amplitude: 0.1, sigma: 0.8)
    let segments = Self.detect(plane)
    try #require(segments.count == 2)
    let between = abs(TrailSynth.angle(segments[0]) - TrailSynth.angle(segments[1]))
    #expect(abs(between - 90) <= 6)
  }

  @Test("a textured field (40% bright cells) is refused outright")
  func testTexturedField() {
    var plane = Self.plane(seed: 4)
    var random = SeededGaussian(seed: 5)
    for index in plane.indices where random.uniform() < 0.4 { plane[index] += 0.1 }
    #expect(Self.detect(plane).isEmpty)
  }

  /// Seed 7: the confirmation keeps any two-cell component within ⊥2 of the line, so an adjacent
  /// pair of 2.5σ noise cells far along the line stretches the extent past the gate — as in the
  /// legacy rule. This stream's seed 6 puts one at (6, 4)–(6, 5); Go's seed 6 had none.
  @Test("a streak spanning under a quarter of the frame is not a trail")
  func testShortStreak() {
    var plane = Self.plane(seed: 7)
    TrailSynth.addStreak(
      &plane, width: Self.side, height: Self.side, from: (130, 130), to: (170, 170),
      amplitude: 0.1, sigma: 0.8)
    #expect(Self.detect(plane).isEmpty)
  }

  @Test(
    "degenerate input yields nothing",
    arguments: [
      ([Float](), 0, 0), ([Float](repeating: 0, count: 10), 5, 2),
      ([Float](repeating: 0, count: 100), 40, 40), ([Float](repeating: 0, count: 1600), 40, 40),
    ])
  func testDegenerate(plane: [Float], width: Int, height: Int) {
    #expect(
      TrailSegmentDetector.detect(plane, width: width, height: height, params: .residual(k: 5))
        .isEmpty)
  }

  @Test("a horizontal σ⊥ = 2 streak refines to FWHM ≈ 4.71 px (±1)")
  func testGaussianWidth() throws {
    var plane = Self.plane(background: 0.05, sigma: 0.003, seed: 10)
    TrailSynth.addStreak(
      &plane, width: Self.side, height: Self.side, from: (75, 150), to: (225, 150),
      amplitude: 0.05, sigma: 2)
    let segments = Self.detect(plane)
    let segment = try #require(segments.count == 1 ? segments.first : nil)
    #expect(abs(segment.width - 4.71) <= 1)
  }

  @Test("a streak over 60% of the frame extends to the image borders")
  func testExtentToBorders() throws {
    var plane = Self.plane(background: 0.05, sigma: 0.003, seed: 11)
    TrailSynth.addStreak(
      &plane, width: Self.side, height: Self.side, from: (45, 150), to: (255, 150),
      amplitude: 0.4, sigma: 0.8)
    let segments = Self.detect(plane)
    let segment = try #require(segments.count == 1 ? segments.first : nil)
    let extent = segment.t1 - segment.t0
    #expect(extent > TrailSynth.span(segment, [(45, 150), (255, 150)]) && extent >= 0.9 * 300)
  }

  @Test("a shorter streak is padded at its endpoints, short of the borders")
  func testExtentEndpointPad() throws {
    var plane = Self.plane(background: 0.05, sigma: 0.003, seed: 12)
    TrailSynth.addStreak(
      &plane, width: Self.side, height: Self.side, from: (100, 150), to: (200, 150),
      amplitude: 0.4, sigma: 0.8)
    let segments = Self.detect(plane)
    let segment = try #require(segments.count == 1 ? segments.first : nil)
    let extent = segment.t1 - segment.t0
    #expect(extent > TrailSynth.span(segment, [(100, 150), (200, 150)]) && extent < 0.9 * 300)
  }

  @Test(
    "the vote fraction defaults to the satellite tuning; an override wins, a negative is ignored",
    arguments: [
      (TrailSegmentDetector.Params.residual(k: 3), 0.25),
      (.raw(k: 5), 0.25),
      (TrailSegmentDetector.Params(mode: .residual, k: 0, voteFraction: 0.08), 0.08),
      (TrailSegmentDetector.Params(mode: .residual, k: 0, voteFraction: -1), 0.25),
    ])
  func testVoteFraction(params: TrailSegmentDetector.Params, expected: Double) {
    #expect(params.effectiveVoteFraction == expected)
  }

  @Test(
    "raw mode ignores k (5σ) unless overridden; residual clamps 0.7·k to [1.5, 2.5]",
    arguments: [
      (TrailSegmentDetector.Params.raw(k: 3), 5.0),
      (.raw(k: 0), 5.0),
      (TrailSegmentDetector.Params(mode: .raw, k: 0, rawSeedK: 12), 12.0),
      (TrailSegmentDetector.Params(mode: .residual, k: 3, rawSeedK: 12), 2.1),
      (.residual(k: 1), 1.5),
      (.residual(k: 9), 2.5),
    ])
  func testSeedK(params: TrailSegmentDetector.Params, expected: Double) {
    #expect(abs(params.seedK - expected) <= 1e-9)
  }
}
