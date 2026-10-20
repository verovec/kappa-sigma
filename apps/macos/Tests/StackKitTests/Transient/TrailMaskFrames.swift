import Foundation
import ImageKit
import StackKit

/// The synthetic sequences of `lineaware_test.go` / `hybrid_test.go`: 300 × 300 mono frames, a
/// 0.05 sky with ±0.005 hash noise, a static 0.9 star, and 45° streaks on y = x.
enum TrailMaskFrames {
  static let side = 300
  static let sky: Float = 0.05
  static let star = (x: 150, y: 60)
  static let starValue: Float = 0.9

  /// Deterministic per-(pixel, frame) noise, so the cross-frame MAD is not zero (`seqNoise`).
  static func noise(_ pixel: Int, _ frame: Int) -> Float {
    var hash = UInt32(truncatingIfNeeded: pixel &* 2_654_435_761 &+ frame &* 40503 &+ 12345)
    hash ^= hash >> 13
    return (Float(hash & 0x3ff) / 1023 - 0.5) * 0.01
  }

  /// Frame `frame`: sky + star, plus a full streak of `amplitude` (0 = none) (`memFrame`).
  static func frame(_ frame: Int, amplitude: Float = 0) -> [Float] {
    var plane = (0..<(side * side)).map { sky + noise($0, frame) }
    plane[star.y * side + star.x] = starValue
    if amplitude > 0 { addStreak(&plane, amplitude: amplitude, along: 30...270) }
    return plane
  }

  /// A Gaussian-profile (σ 1.2) streak on y = x over along = (x + y)/2 ∈ `along`, ⊥ ≤ 3 px.
  static func addStreak(_ plane: inout [Float], amplitude: Float, along: ClosedRange<Double>) {
    let sigma = 1.2
    for y in 0..<side {
      for x in 0..<side where along.contains(Double(x + y) / 2) {
        let distance = Double(abs(x - y)) / 2.0.squareRoot()
        guard distance <= 3 else { continue }
        let value = sky + amplitude * Float(exp(-distance * distance / (2 * sigma * sigma)))
        if value > plane[y * side + x] { plane[y * side + x] = value }
      }
    }
  }

  /// The brightest pixel on the diagonal between 30 and 270.
  static func maxAlongDiagonal(_ plane: [Float]) -> Float {
    (30..<270).map { plane[$0 * side + $0] }.max() ?? 0
  }

  static func starPixel(_ plane: [Float]) -> Float { plane[star.y * side + star.x] }

  /// Writes each frame as `r_light_NNNNN.fits` in the scratch folder.
  static func write(_ frames: [[Float]], in folder: URL) throws -> [URL] {
    try frames.enumerated().map { index, plane in
      try FloatFITS.write(
        folder.appendingPathComponent(String(format: "r_light_%05d.fits", index + 1)),
        width: side, height: side, planes: [plane])
    }
  }

  static func read(_ url: URL) throws -> [Float] {
    try FITSFile.read(at: url).image().planes[0]
  }
}
