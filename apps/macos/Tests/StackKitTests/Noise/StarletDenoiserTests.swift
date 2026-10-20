import Foundation
import StackKit
import Testing

/// `Starlet` and `StarletDenoiser` are `noise/starlet.go` and `noise/weighted.go`: cases translated
/// from `starlet_test.go` and `weighted_test.go` (same tolerances; fixtures from this package's
/// seeded generator instead of Go's).
@Suite("Starlet — the transform, and the weighted, luminance-only denoise")
struct StarletDenoiserTests {
  /// A 0.1 pedestal with σ = 0.01 Gaussian noise.
  static func noisy(_ width: Int, _ height: Int, seed: UInt64) -> [Float] {
    var gaussian = SeededGaussian(seed: seed)
    return (0..<width * height).map { _ in Float(0.1 + 0.01 * gaussian.next()) }
  }

  /// The variance of columns x0..<x1 (comparisons only need monotonicity).
  static func variance(_ plane: [Float], width: Int, columns: Range<Int>, height: Int) -> Double {
    let values = (0..<height).flatMap { row in columns.map { Double(plane[row * width + $0]) } }
    let mean = values.reduce(0, +) / Double(values.count)
    return values.map { $0 * $0 }.reduce(0, +) / Double(values.count) - mean * mean
  }

  static func std(_ plane: [Float], width: Int, height: Int, margin: Int) -> Double {
    let values = (margin..<(height - margin)).flatMap { row in
      (margin..<(width - margin)).map { Double(plane[row * width + $0]) }
    }
    let mean = values.reduce(0, +) / Double(values.count)
    return max(0, values.map { $0 * $0 }.reduce(0, +) / Double(values.count) - mean * mean).squareRoot()
  }

  @Test("decompose then reconstruct is exact to 1e-5 on odd, non-square planes; a flat plane has no detail")
  func testRoundTripAndConstant() {
    let (w, h) = (131, 77)
    let plane = Self.noisy(w, h, seed: 7)
    let (smooth, details) = Starlet.decompose(plane, width: w, height: h, scales: 5)
    let out = Starlet.reconstruct(smooth, details)
    #expect(details.count == 5 && zip(out, plane).allSatisfy { abs($0 - $1) < 1e-5 })
    let flat = [Float](repeating: 0.3, count: 40 * 24)
    let (flatSmooth, flatDetails) = Starlet.decompose(flat, width: 40, height: 24, scales: 4)
    #expect(flatDetails.allSatisfy { Self.std($0, width: 40, height: 24, margin: 0) <= 1e-6 })
    #expect(flatSmooth.allSatisfy { abs($0 - 0.3) <= 1e-5 })
  }

  @Test("white noise of unit variance reproduces the tabulated detail sigmas within 3%")
  func testSigmaPropagation() {
    let size = 512
    var gaussian = SeededGaussian(seed: 12345)
    let plane = (0..<size * size).map { _ in Float(gaussian.next()) }
    let (_, details) = Starlet.decompose(plane, width: size, height: size, scales: 6)
    for (scale, expected) in [0.8907, 0.2007, 0.0855, 0.0412].enumerated() {
      let measured = Self.std(details[scale], width: size, height: size, margin: 40)
      #expect(abs(measured - expected) <= 0.03 * expected, "scale \(scale): \(measured)")
    }
  }

  @Test("weight 0 touches no byte; a weighted half is denoised there only")
  func testWeights() {
    let small = Self.noisy(128, 128, seed: 11)
    var untouched = [small]
    StarletDenoiser.denoise(&untouched, width: 128, height: 128, weights: .init(repeating: 0, count: 128 * 128))
    #expect(untouched[0] == small)

    let (w, h) = (256, 256)
    let original = Self.noisy(w, h, seed: 23)
    var planes = [original]
    let weights = (0..<w * h).map { $0 % w >= w / 2 ? Float(1.5) : 0 }
    StarletDenoiser.denoise(&planes, width: w, height: h, weights: weights)
    #expect((0..<h).allSatisfy { row in planes[0][(row * w)..<(row * w + w / 2)] == original[(row * w)..<(row * w + w / 2)] })
    let before = Self.variance(original, width: w, columns: (w / 2 + 8)..<(w - 8), height: h)
    let after = Self.variance(planes[0], width: w, columns: (w / 2 + 8)..<(w - 8), height: h)
    #expect(after < before * 0.8)
  }

  @Test("colour: chroma survives exactly, the luminance is denoised; weight 0 leaves every plane")
  func testColour() {
    let (w, h) = (256, 256)
    let mean = Self.noisy(w, h, seed: 31)
    let chroma = (0..<w * h).map { 0.004 * Float($0 % w % 64) / 64 }
    let original = [
      zip(mean, chroma).map { $0 + $1 }, zip(mean, chroma).map { $0 - $1 / 2 }, zip(mean, chroma).map { $0 - $1 / 2 },
    ]
    var planes = original
    let weights = (0..<w * h).map { $0 % w >= w / 2 ? Float(2) : 0 }
    StarletDenoiser.denoise(&planes, width: w, height: h, weights: weights)
    let after = (0..<w * h).map { (planes[0][$0] + planes[1][$0] + planes[2][$0]) / 3 }
    #expect((0..<w * h).allSatisfy { abs(Double(chroma[$0]) - Double(planes[0][$0] - after[$0])) <= 1e-5 })
    let columns = (w / 2 + 8)..<(w - 8)
    #expect(Self.variance(after, width: w, columns: columns, height: h) < Self.variance(mean, width: w, columns: columns, height: h) * 0.8)
    var zero = original
    StarletDenoiser.denoise(&zero, width: w, height: h, weights: .init(repeating: 0, count: w * h))
    #expect(zero == original)
  }

  @Test("the measured sigma of a σ = 0.01 field is ~0.01")
  func testMeasure() {
    let sigma = StarletDenoiser.measure(Self.noisy(256, 256, seed: 5), width: 256, height: 256)
    #expect(abs(sigma - 0.01) <= 0.001)
  }
}
