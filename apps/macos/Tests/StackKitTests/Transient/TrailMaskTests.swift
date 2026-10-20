import Foundation
import StackKit
import Testing

/// `TrailMask.mask` ports `transient.MaskCrossFrameValidated`: cases of `hybrid_test.go`, plus
/// the per-pixel cases of `transient_test.go` and `lineaware_test.go` that its blanket pass keeps.
@Suite("TrailMask — cross-frame transients removed from registered frames")
struct TrailMaskTests {
  typealias F = TrailMaskFrames

  static func mask(_ frames: inout [[Float]], k: Double = 3) async throws -> TrailMaskReport {
    var planes = frames.map { [$0] }
    let report = try await TrailMask.mask(&planes, width: F.side, height: F.side, k: k)
    frames = planes.map { $0[0] }
    return report
  }

  @Test("a streak in one frame is accepted, painted to the median; the star survives (±0.05)")
  func testOneFrameTrail() async throws {
    var frames = (0..<8).map { F.frame($0, amplitude: $0 == 0 ? 0.6 : 0) }
    let summary = try await Self.mask(&frames).summary
    #expect(summary.segments >= 1 && summary.rejected == 0)
    #expect(F.maxAlongDiagonal(frames[0]) < 0.2)
    #expect(frames.allSatisfy { abs(F.starPixel($0) - F.starValue) <= 0.05 })
  }

  @Test("the same corridor lit in 4 of 10 frames is rejected as fixed pattern by the line pass")
  func testFixedPattern() async throws {
    var frames = (0..<10).map { F.frame($0, amplitude: $0 < 4 ? 0.6 : 0) }
    let summary = try await Self.mask(&frames).summary
    #expect(summary.rejected > 0 && summary.segments == 0 && summary.geostationary == 0)
  }

  @Test("four distinct streaks in one frame are all validated and painted")
  func testFourLines() async throws {
    var frames = (0..<8).map { F.frame($0) }
    Self.paintFourLines(&frames[0])
    let summary = try await Self.mask(&frames).summary
    #expect(summary.segments >= 3 && summary.rejected == 0)
    #expect(((40..<260).map { frames[0][75 * F.side + $0] }.max() ?? 1) < 0.2)
    #expect(abs(F.starPixel(frames[0]) - F.starValue) <= 0.05)
  }

  @Test("a track reused frame after frame is found on the mean residual and repaired in each")
  func testMarchingBelt() async throws {
    var frames = (0..<8).map { F.frame($0) }
    for index in frames.indices {
      let start = 20 + 34 * Double(index)
      F.addStreak(&frames[index], amplitude: 0.6, along: start...(start + 30))
    }
    let summary = try await Self.mask(&frames).summary
    #expect(summary.recurring >= 1)
    for (index, plane) in frames.enumerated() {
      let middle = Int(20 + 34 * Double(index) + 15)
      #expect(plane[middle * F.side + middle] < 0.2)
      #expect(abs(F.starPixel(plane) - F.starValue) <= 0.05)
    }
  }

  @Test("zero-fill borders neither dilute a trail nor read as a dark witness")
  func testZeroBorder() async throws {
    var frames = (0..<8).map { F.frame($0) }
    F.addStreak(&frames[0], amplitude: 0.6, along: 30...270)
    for index in 0..<3 {
      for y in 0..<F.side { for x in 0..<100 { frames[index][y * F.side + x] = 0 } }
    }
    let summary = try await Self.mask(&frames).summary
    #expect(summary.segments >= 1 && summary.rejected == 0)
    #expect(((110..<260).map { frames[0][$0 * F.side + $0] }.max() ?? 1) < 0.2)
    #expect((0..<90).allSatisfy { frames[1][60 * F.side + $0] == 0 })
  }

  @Test("a clean sequence: no segment, a negligible blanket clean-up, the star kept (±0.02)")
  func testCleanSequence() async throws {
    var frames = (0..<6).map { F.frame($0) }
    let summary = try await Self.mask(&frames).summary
    #expect(summary.segments == 0)
    #expect(Double(summary.maskedPixels) < 0.01 * Double(6 * F.side * F.side))
    #expect(abs(F.starPixel(frames[0]) - F.starValue) <= 0.02)
  }

  @Test("a transient moving pixel to pixel is cleaned; the jittering static star is kept (±10)")
  func testMovingTransient() async throws {
    let (count, side, star) = (8, 20, 5 * 20 + 5)
    var frames = (0..<count).map { frame -> [[Float]] in
      var plane = (0..<(side * side)).map { 100 + Float((frame * 7 + $0 * 3) % 5) - 2 }
      plane[star] = 500 + Float((frame * 3) % 5) - 2
      plane[frame * side + 2] = 900
      return [plane]
    }
    let report = try await TrailMask.mask(&frames, width: side, height: side, k: 3)
    #expect(report.summary.maskedPixels >= count)
    for (frame, planes) in frames.enumerated() {
      #expect(planes[0][frame * side + 2] < 200 && abs(planes[0][star] - 500) <= 10)
    }
  }

  @Test("under five frames, or k ≤ 0, nothing is touched", arguments: [(4, 3.0), (7, 0.0)])
  func testNoOp(count: Int, k: Double) async throws {
    var frames = (0..<count).map { frame -> [[Float]] in
      var plane = [Float](repeating: 0, count: 64)
      plane[10] = Float(1000 * frame)
      return [plane]
    }
    let before = frames
    let report = try await TrailMask.mask(&frames, width: 8, height: 8, k: k)
    #expect(report.summary.maskedPixels == 0 && frames == before)
  }

  @Test("frames of another size are refused")
  func testMismatchedFrames() async {
    var frames = (0..<5).map { _ in [[Float](repeating: 0, count: 64)] }
    frames[2] = [[Float](repeating: 0, count: 72)]
    await #expect(throws: TrailMaskError.self) {
      try await TrailMask.mask(&frames, width: 8, height: 8, k: 3)
    }
  }

  /// Four 0.8 bands: horizontal, vertical and both diagonals (`paintFourLines`).
  static func paintFourLines(_ plane: inout [Float]) {
    let side = F.side
    func set(_ x: Int, _ y: Int) {
      if x >= 0, x < side, y >= 0, y < side, plane[y * side + x] < 0.8 { plane[y * side + x] = 0.8 }
    }
    for t in 20..<(side - 20) {
      for d in -2...2 {
        set(t, 75 + d)
        set(75 + d, t)
        set(t, t + d)
        set(t, side - 1 - t + d)
      }
    }
  }
}
