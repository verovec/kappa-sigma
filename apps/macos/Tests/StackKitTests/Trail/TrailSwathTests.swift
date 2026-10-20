import Foundation
import StackKit
import Testing

/// `TrailSwath` ports `trail.ApplySwathMedian` / `ApplySwathLocalBG` and `Segment.Contains`:
/// cases of `mask_test.go`.
@Suite("TrailSwath — a segment's swath painted from the median or the local sky")
struct TrailSwathTests {
  /// A plane rising along y, so perpendicular samples of a horizontal swath have a real spread.
  static func gradient(_ width: Int, _ height: Int) -> [Float] {
    (0..<(width * height)).map { Float(0.1 + 0.0005 * Double($0 / width)) }
  }

  /// The line y = `row` over the whole width.
  static func horizontal(_ row: Double, width: Double) -> TrailSegment {
    TrailSegment(nx: 0, ny: 1, rho: row, t0: -1e6, t1: 1e6, width: width)
  }

  static func swathStats(_ plane: [Float], width: Int, height: Int, _ segment: TrailSegment)
    -> (mean: Double, variance: Double, pixels: Int)
  {
    var (sum, squares, count) = (0.0, 0.0, 0)
    for y in 0..<height {
      for x in 0..<width where segment.contains(x: Double(x), y: Double(y)) {
        let value = Double(plane[y * width + x])
        sum += value
        squares += value * value
        count += 1
      }
    }
    guard count > 0 else { return (0, 0, 0) }
    let mean = sum / Double(count)
    return (mean, squares / Double(count) - mean * mean, count)
  }

  @Test("the local fill matches the sky at the swath centre (±0.02) and carries noise")
  func testLocalBackgroundMatchesSky() throws {
    var plane = Self.gradient(200, 200)
    let segment = Self.horizontal(100, width: 4)
    let painted = TrailSwath.paintLocalBackground(
      &plane, width: 200, height: 200, segment: segment, seed: 42)
    let stats = Self.swathStats(plane, width: 200, height: 200, segment)
    try #require(painted > 0 && stats.pixels > 0)
    #expect(abs(stats.mean - (0.1 + 0.0005 * 100)) <= 0.02 && stats.variance > 0)
  }

  @Test("the local fill is deterministic per seed")
  func testLocalBackgroundDeterministic() {
    var (first, second) = (Self.gradient(200, 200), Self.gradient(200, 200))
    let segment = Self.horizontal(100, width: 4)
    let counts = (
      TrailSwath.paintLocalBackground(&first, width: 200, height: 200, segment: segment, seed: 99),
      TrailSwath.paintLocalBackground(&second, width: 200, height: 200, segment: segment, seed: 99)
    )
    #expect(counts.0 == counts.1 && first == second)
  }

  @Test("a star off the swath is never touched")
  func testLocalBackgroundLeavesStar() {
    var plane = Self.gradient(200, 200)
    plane[30 * 200 + 100] = 5
    _ = TrailSwath.paintLocalBackground(
      &plane, width: 200, height: 200, segment: Self.horizontal(100, width: 4), seed: 7)
    #expect(plane[30 * 200 + 100] == 5)
  }

  @Test(
    "the swath honours the extent and ±Width of the line",
    arguments: [(100.0, 100.0, true), (10, 100, false), (100, 110, false)])
  func testContains(x: Double, y: Double, expected: Bool) {
    let segment = TrailSegment(nx: 0, ny: 1, rho: 100, t0: -150, t1: -50, width: 4)
    #expect(segment.contains(x: x, y: y) == expected)
  }

  @Test("the median paint replaces the swath only; a size mismatch is a no-op")
  func testMedianPaint() {
    var plane = Self.gradient(120, 120)
    let median = [Float](repeating: 0.2, count: 120 * 120)
    let segment = Self.horizontal(60, width: 4)
    let before = plane[10 * 120 + 5]
    let painted = TrailSwath.paintMedian(
      &plane, median: median, width: 120, height: 120, segment: segment)
    #expect(painted > 0 && plane[60 * 120 + 30] == 0.2 && plane[10 * 120 + 5] == before)
    #expect(
      TrailSwath.paintMedian(
        &plane, median: Array(median.prefix(10)), width: 120, height: 120, segment: segment) == 0)
  }
}
