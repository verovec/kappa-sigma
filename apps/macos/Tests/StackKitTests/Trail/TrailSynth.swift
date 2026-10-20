import Foundation
import StackKit

/// Synthetic planes of `trail/synth_test.go`: Gaussian sky and Gaussian-profile streaks.
enum TrailSynth {
  /// A `width` × `height` plane of `background` + N(0, `sigma`) noise, deterministic per seed.
  static func noisyPlane(width: Int, height: Int, background: Double, sigma: Double, seed: UInt64)
    -> [Float]
  {
    var random = SeededGaussian(seed: seed)
    return (0..<(width * height)).map { _ in Float(background + random.next() * sigma) }
  }

  /// Adds a straight streak from (ax, ay) to (bx, by): amp·exp(−d²/2σ²) on every pixel whose
  /// projection lies on the segment, d its perpendicular distance.
  static func addStreak(
    _ plane: inout [Float], width: Int, height: Int, from a: (Double, Double),
    to b: (Double, Double), amplitude: Double, sigma: Double
  ) {
    let (dx, dy) = (b.0 - a.0, b.1 - a.1)
    let length = hypot(dx, dy)
    let (ux, uy) = (dx / length, dy / length)
    let (nx, ny) = (-uy, ux)
    for y in 0..<height {
      for x in 0..<width {
        let (rx, ry) = (Double(x) - a.0, Double(y) - a.1)
        let along = rx * ux + ry * uy
        guard along >= 0, along <= length else { continue }
        let distance = rx * nx + ry * ny
        plane[y * width + x] += Float(amplitude * exp(-distance * distance / (2 * sigma * sigma)))
      }
    }
  }

  /// The segment's orientation folded into [0, 180) degrees.
  static func angle(_ segment: TrailSegment) -> Double {
    let (dx, dy) = segment.direction
    return fmod(atan2(dy, dx) * 180 / .pi + 180, 180)
  }

  /// The extent of `points` projected on the segment's line.
  static func span(_ segment: TrailSegment, _ points: [(Double, Double)]) -> Double {
    let projected = points.map { segment.project(x: $0.0, y: $0.1) }
    return (projected.max() ?? 0) - (projected.min() ?? 0)
  }
}
