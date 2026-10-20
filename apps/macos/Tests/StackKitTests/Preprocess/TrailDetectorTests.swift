import StackKit
import Testing

/// Translated from `internal/grade/trails_test.go`: the same deterministic field (LCG noise, 30
/// star blobs) with and without a straight streak.
@Suite("TrailDetector — a long bright streak in a downsampled frame")
struct TrailDetectorTests {
  static func grid(width: Int, height: Int, trail: Bool) -> [Double] {
    var seed: UInt32 = 12345
    func random() -> Double {
      seed = seed &* 1_664_525 &+ 1_013_904_223
      return Double(seed >> 8 & 0xffff) / 65536
    }
    var grid = (0..<width * height).map { _ in 100 + (random() - 0.5) * 10 }
    for _ in 0..<30 {
      let (cx, cy) = (Int(random() * Double(width)), Int(random() * Double(height)))
      for dy in -1...1 {
        for dx in -1...1 where (0..<width).contains(cx + dx) && (0..<height).contains(cy + dy) {
          grid[(cy + dy) * width + cx + dx] += 3000
        }
      }
    }
    if trail {
      for step in stride(from: 0.0, to: 1, by: 0.002) {
        let x = Int(5 + step * Double(width - 10))
        let y = Int(8 + step * Double(height - 20))
        guard (0..<width).contains(x), (0..<height).contains(y) else { continue }
        grid[y * width + x] += 6000
        if x + 1 < width { grid[y * width + x + 1] += 6000 }
      }
    }
    return grid
  }

  @Test("a star field is not flagged; a clear streak is")
  func testTrailDetector_detects() {
    #expect(!TrailDetector.detect(Self.grid(width: 200, height: 200, trail: false), width: 200, height: 200).detected)
    let streak = TrailDetector.detect(Self.grid(width: 200, height: 200, trail: true), width: 200, height: 200)
    #expect(streak.detected)
    #expect(streak.score > TrailDetector.voteFraction)
  }

  @Test("too small, flat or mismatched grids say nothing")
  func testTrailDetector_guards() {
    #expect(TrailDetector.detect([Double](repeating: 1, count: 100), width: 10, height: 10) == (false, 0))
    #expect(TrailDetector.detect([Double](repeating: 1, count: 400), width: 20, height: 20) == (false, 0))
    #expect(TrailDetector.detect([1, 2, 3], width: 20, height: 20) == (false, 0))
  }
}
