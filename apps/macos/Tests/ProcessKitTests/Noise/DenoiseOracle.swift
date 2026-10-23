import Foundation
import ProcessKit
import StackKit

/// The Studio denoise on the CPU, built from StackKit's starlet (`Starlet`, the per-scale
/// `StarletDenoiser.shrink` and its SNR protection), not from the kernel.
enum DenoiseOracle {
  struct Values {
    var strengths = [3.0, 2.5, 1.8, 1.0]
    var amount = 1.0
    var luminance = 1.0
    var chrominance = 1.0
    var protectStars = false
  }

  static func denoise(
    _ planes: [[Float]], width: Int, height: Int, stats: LayerStats, values: Values
  ) -> [[Float]] {
    let denoised = planes.indices.map { channel in
      let plane = stats.channels[min(channel, stats.channels.count - 1)]
      return denoisePlane(
        planes[channel], width: width, height: height, median: plane.median, sigma: plane.madn,
        values: values)
    }
    let lum = values.amount * values.luminance
    let chroma = values.amount * values.chrominance
    guard planes.count == 3 else {
      return zip(planes, denoised).map { input, output in
        zip(input, output).map { Float(Double($0) + lum * (Double($1) - Double($0))) }
      }
    }
    return (0..<3).map { channel in
      (0..<(width * height)).map { index in
        let input = (0..<3).map { Double(planes[$0][index]) }
        let output = (0..<3).map { Double(denoised[$0][index]) }
        let luma = input.reduce(0, +) / 3
        let lumaOut = output.reduce(0, +) / 3
        let colourChange = (output[channel] - lumaOut) - (input[channel] - luma)
        return Float(input[channel] + lum * (lumaOut - luma) + chroma * colourChange)
      }
    }
  }

  static func denoisePlane(
    _ plane: [Float], width: Int, height: Int, median: Double, sigma: Double, values: Values
  ) -> [Float] {
    var (smooth, details) = Starlet.decompose(
      plane, width: width, height: height, scales: values.strengths.count)
    let scaleTwo = Starlet.decompose(plane, width: width, height: height, scales: 2).smooth
    let protect: (Int) -> Double = { index in
      guard values.protectStars else { return 0 }
      guard sigma > 0 else { return 1 }
      return StarletDenoiser.protection(snr: (Double(scaleTwo[index]) - median) / sigma)
    }
    for (scale, strength) in values.strengths.enumerated() {
      let threshold = strength * Starlet.scaleSigma(scale) * sigma
      details[scale] = StarletDenoiser.shrink(
        details[scale], threshold: { _ in threshold }, protect: protect)
    }
    smooth = Starlet.reconstruct(smooth, details)
    return smooth
  }

  /// A deterministic Gaussian noise field (Box–Muller over a 64-bit LCG).
  static func noise(count: Int, sigma: Double, seed: UInt64) -> [Float] {
    var state = seed
    func uniform() -> Double {
      state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      return (Double(state >> 11) + 0.5) / Double(1 << 53)
    }
    return (0..<count).map { _ in
      Float(sigma * (-2 * log(uniform())).squareRoot() * cos(2 * .pi * uniform()))
    }
  }

  /// The median absolute deviation from the median.
  static func mad(_ values: [Float]) -> Double {
    func median(_ list: [Double]) -> Double {
      let sorted = list.sorted()
      let middle = sorted.count / 2
      return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }
    let doubles = values.map(Double.init)
    let centre = median(doubles)
    return median(doubles.map { abs($0 - centre) })
  }
}
