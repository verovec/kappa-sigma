import Foundation

/// hdrcomp (the v9 runbook's two-scale HDR, recorded by 0067 under
/// `~/Documents/astro/fixtures/finish/tools-src/hdrcomp`), in double, written from its source
/// and not from the kernel.
///
/// L = mean(R, G, B) in float32; base = grey opening of L (square window clipped to the image);
/// smooth = three box passes approximating a Gaussian of σ (Kovesi's widths, each window summed
/// in double, clamped at the edges); above t1 the smooth part becomes t1 + s·asinh((smooth −
/// t1)/s), the detail L − smooth is put back, and the ratio L′/L (1 where L ≤ 1e-9) scales every
/// plane. One deliberate departure from hdrcomp: the ratio is floored at 0, so a dead pixel
/// inside a compressed core goes black instead of strongly negative.
enum HDROracle {
  /// mean(R, G, B) in float32, as hdrcomp sums it; a mono image is its own luminance.
  static func luminance(_ planes: [[Float]]) -> [Float] {
    guard planes.count == 3 else { return planes[0] }
    return (0..<planes[0].count).map { (planes[0][$0] + planes[1][$0] + planes[2][$0]) / 3 }
  }

  /// hdrcomp's own sky: the median of every 97th luminance pixel (the upper middle one).
  static func legacySky(_ luminance: [Float]) -> Double {
    let sample = stride(from: 0, to: luminance.count, by: 97).map { Double(luminance[$0]) }.sorted()
    return sample[sample.count / 2]
  }

  /// The three odd box widths approximating a Gaussian of `sigma` (imgops `boxesForGauss`).
  static func boxes(sigma: Double) -> [Int] {
    let ideal = (12 * sigma * sigma / 3 + 1).squareRoot()
    var lower = Int(ideal.rounded(.down))
    if lower % 2 == 0 { lower -= 1 }
    let split =
      (12 * sigma * sigma - Double(3 * lower * lower) - Double(12 * lower) - 9)
      / Double(-4 * lower - 4)
    let count = Int(split.rounded())
    return (0..<3).map { $0 < count ? lower : lower + 2 }
  }

  /// imgops `GaussianBlur`: the boxes of radius ≥ 1, each along x then y.
  static func gaussian(_ plane: [Float], width: Int, height: Int, sigma: Double) -> [Float] {
    guard sigma > 0 else { return plane }
    var out = plane
    for box in boxes(sigma: sigma) where (box - 1) / 2 >= 1 {
      let radius = (box - 1) / 2
      out = boxPass(out, width: width, height: height, radius: radius, alongX: true)
      out = boxPass(out, width: width, height: height, radius: radius, alongX: false)
    }
    return out
  }

  /// A moving average of `radius`, edge-clamped, accumulated in double.
  static func boxPass(_ plane: [Float], width: Int, height: Int, radius: Int, alongX: Bool)
    -> [Float]
  {
    var out = plane
    let (length, lines) = alongX ? (width, height) : (height, width)
    let index = { (line: Int, at: Int) in alongX ? line * width + at : at * width + line }
    for line in 0..<lines {
      for at in 0..<length {
        var sum = 0.0
        for offset in -radius...radius {
          sum += Double(plane[index(line, min(max(at + offset, 0), length - 1))])
        }
        out[index(line, at)] = Float(sum / Double(2 * radius + 1))
      }
    }
    return out
  }

  /// The ratio L′/L of each pixel for `luminance` and its `smooth` part (hdrcomp's main loop).
  static func ratios(luminance: [Float], smooth: [Float], t1: Double, softness: Double) -> [Float] {
    zip(luminance, smooth).map { value, smoothed in
      let (lum, ls) = (Double(value), Double(smoothed))
      // hdrcomp computes (ls + lum − ls) / lum below the knee: 1 up to rounding, exactly 1 here.
      guard ls > t1, lum > 1e-9 else { return 1 }
      let compressed = t1 + softness * asinh((ls - t1) / softness)
      return Float(max((compressed + lum - ls) / lum, 0))
    }
  }

  /// The whole process on planar `planes`, with absolute thresholds `t1` and `softness`.
  static func render(
    _ planes: [[Float]], size: (width: Int, height: Int), t1: Double, softness: Double,
    sigma: Double, openRadius: Int
  ) -> [[Float]] {
    let (lum, width, height) = (luminance(planes), size.width, size.height)
    // hdrcomp's `opening` (min then max windows clipped to the image) is the shared oracle's.
    let base = MorphologyOracle.opening(lum, width: width, height: height, radius: openRadius)
    let smooth = gaussian(base, width: width, height: height, sigma: sigma)
    let ratio = ratios(luminance: lum, smooth: smooth, t1: t1, softness: softness)
    return planes.map { plane in zip(plane, ratio).map { $0 * $1 } }
  }
}
