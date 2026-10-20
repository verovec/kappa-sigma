/// The à-trous B3-spline starlet transform (`noise/starlet.go`): a redundant multiscale
/// decomposition whose planes add back to the input exactly.
package enum Starlet {
  /// Per scale, the sigma of a detail plane of unit-variance white noise.
  static let whiteNoiseSigma = [0.8907, 0.2007, 0.0855, 0.0412, 0.0205, 0.0107]

  /// The white-noise detail sigma at scale j, halving per octave past the table.
  static func scaleSigma(_ scale: Int) -> Double {
    let index = max(0, scale)
    guard index >= whiteNoiseSigma.count, let last = whiteNoiseSigma.last else {
      return whiteNoiseSigma[index]
    }
    return (whiteNoiseSigma.count...index).reduce(last) { value, _ in value * 0.5 }
  }

  /// The coarsest smooth and the `scales` detail planes (wⱼ = cⱼ − cⱼ₊₁).
  package static func decompose(_ plane: [Float], width: Int, height: Int, scales: Int)
    -> (smooth: [Float], details: [[Float]])
  {
    var current = plane
    var details: [[Float]] = []
    for scale in 0..<scales {
      let next = smooth(current, width: width, height: height, step: 1 << scale)
      details.append(zip(current, next).map { $0 - $1 })
      current = next
    }
    return (current, details)
  }

  /// smooth + Σ details, the exact inverse.
  package static func reconstruct(_ smooth: [Float], _ details: [[Float]]) -> [Float] {
    var out = smooth
    for detail in details {
      for index in out.indices { out[index] += detail[index] }
    }
    return out
  }

  /// One separable B3 pass at dilation `step` (rows, then columns).
  static func smooth(_ source: [Float], width: Int, height: Int, step: Int) -> [Float] {
    var rows = [Float](repeating: 0, count: source.count)
    var out = [Float](repeating: 0, count: source.count)
    source.withUnsafeBufferPointer { src in
      rows.withUnsafeMutableBufferPointer { dst in
        for row in 0..<height {
          let base = row * width
          for column in 0..<width {
            dst[base + column] = kernel(
              src[base + reflect(column - 2 * step, width)],
              src[base + reflect(column - step, width)],
              src[base + column], src[base + reflect(column + step, width)],
              src[base + reflect(column + 2 * step, width)])
          }
        }
      }
    }
    rows.withUnsafeBufferPointer { src in
      out.withUnsafeMutableBufferPointer { dst in
        for row in 0..<height {
          let (r0, r1) = (
            reflect(row - 2 * step, height) * width, reflect(row - step, height) * width
          )
          let (r3, r4) = (
            reflect(row + step, height) * width, reflect(row + 2 * step, height) * width
          )
          let r2 = row * width
          for column in 0..<width {
            dst[r2 + column] = kernel(
              src[r0 + column], src[r1 + column], src[r2 + column], src[r3 + column],
              src[r4 + column])
          }
        }
      }
    }
    return out
  }

  /// (1/16)·(a + 4b + 6c + 4d + e) in float32, the products fused as arm64 Go fuses them.
  @inline(__always)
  static func kernel(
    _ outerLeft: Float, _ innerLeft: Float, _ centre: Float, _ innerRight: Float,
    _ outerRight: Float
  ) -> Float {
    var sum = outerLeft.addingProduct(4, innerLeft)
    sum = sum.addingProduct(6, centre)
    sum = sum.addingProduct(4, innerRight)
    return Float(1.0 / 16.0) * (sum + outerRight)
  }

  /// Half-sample symmetric reflection into [0, n): −1 → 0, n → n − 1.
  @inline(__always)
  static func reflect(_ index: Int, _ count: Int) -> Int {
    guard count > 1 else { return 0 }
    var value = index
    while value < 0 || value >= count {
      if value < 0 { value = -value - 1 }
      if value >= count { value = 2 * count - value - 1 }
    }
    return value
  }
}
