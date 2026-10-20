internal import Foundation

/// Paints a segment's swath out of a plane (`trail.ApplySwathMedian`, `ApplySwathLocalBG`).
package enum TrailSwath {
  /// Replaces every swath pixel with the co-located `median` value; returns the pixels changed,
  /// 0 on a size mismatch.
  @discardableResult
  package static func paintMedian(
    _ plane: inout [Float], median: [Float], width: Int, height: Int, segment: TrailSegment
  ) -> Int {
    guard plane.count == width * height, median.count == width * height else { return 0 }
    let box = segment.boundingBox(width: width, height: height)
    var painted = 0
    for y in box.y0...box.y1 {
      for x in box.x0...box.x1 where segment.contains(x: Double(x), y: Double(y)) {
        plane[y * width + x] = median[y * width + x]
        painted += 1
      }
    }
    return painted
  }

  /// Paints every swath pixel with the local sky: up to 8 off-swath samples per side along the
  /// perpendicular at 1.5–3 widths, their median plus N(0, 1.4826·MAD) when at least 4 were
  /// found. `seed` makes the noise deterministic; returns the pixels changed.
  @discardableResult
  package static func paintLocalBackground(
    _ plane: inout [Float], width: Int, height: Int, segment: TrailSegment, seed: UInt64
  ) -> Int {
    guard plane.count == width * height else { return 0 }
    var random = SeededGaussian(seed: seed)
    let box = segment.boundingBox(width: width, height: height)
    var painted = 0
    var samples: [Double] = []
    samples.reserveCapacity(16)
    for y in box.y0...box.y1 {
      for x in box.x0...box.x1 where segment.contains(x: Double(x), y: Double(y)) {
        sampleSides(plane, width: width, height: height, segment: segment, x: x, y: y,
          random: &random, into: &samples)
        guard !samples.isEmpty else { continue }
        let (background, sigma) = TrailSegmentDetector.robustStats(samples)
        plane[y * width + x] = Float(
          samples.count >= 4 ? background + random.next() * sigma : background)
        painted += 1
      }
    }
    return painted
  }

  /// Draws 8 perpendicular offsets per side, so the stream advances the same way whatever lands
  /// in bounds, keeping the in-bounds off-swath values.
  private static func sampleSides(
    _ plane: [Float], width: Int, height: Int, segment: TrailSegment, x: Int, y: Int,
    random: inout SeededGaussian, into samples: inout [Double]
  ) {
    samples.removeAll(keepingCapacity: true)
    let (low, high) = (1.5 * segment.width, 3.0 * segment.width)
    for side in [-1.0, 1.0] {
      for _ in 0..<8 {
        let distance = low + (high - low) * random.uniform()
        let sx = Int((Double(x) + side * distance * segment.nx).rounded())
        let sy = Int((Double(y) + side * distance * segment.ny).rounded())
        guard sx >= 0, sx < width, sy >= 0, sy < height,
          !segment.contains(x: Double(sx), y: Double(sy))
        else { continue }
        samples.append(Double(plane[sy * width + sx]))
      }
    }
  }
}
