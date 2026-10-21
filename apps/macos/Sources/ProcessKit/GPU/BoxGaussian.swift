package import Metal

/// The legacy `imgops.GaussianBlur`: three `BoxBlur` passes of Kovesi's widths for σ.
///
/// `boxesForGauss(σ, 3)`, rounding half away from zero, a radius below 1 skipped (hdrcomp's own
/// widths differ: `HDRProcess` keeps them).
package struct BoxGaussian {
  private let blur: BoxBlur

  /// The blur on `device`.
  package init(device: MTLDevice) throws {
    blur = try BoxBlur(device: device)
  }

  /// The radii of the three boxes approximating a Gaussian of `sigma` pixels (`boxesForGauss`;
  /// a radius below 1 is skipped).
  package static func radii(sigma: Double) -> [Int] {
    guard sigma > 0 else { return [] }
    let ideal = (12 * sigma * sigma / 3 + 1).squareRoot()
    var lower = Int(ideal.rounded(.down))
    if lower % 2 == 0 { lower -= 1 }
    let numerator = 12 * sigma * sigma - Double(3 * lower * lower) - Double(12 * lower) - 9
    let small = (numerator / Double(-4 * lower - 4)).rounded()
    return (0..<3).map { Double($0) < small ? lower : lower + 2 }.map { ($0 - 1) / 2 }
      .filter { $0 >= 1 }
  }

  /// Encodes `source` blurred by `sigma` pixels into `target` (one plane each, one size; a σ
  /// with no radius ≥ 1 copies).
  package func encode(
    _ source: MTLTexture, into target: MTLTexture, sigma: Double, commands: MTLCommandBuffer
  ) throws {
    try blur.encode(source, into: target, radii: Self.radii(sigma: sigma), commands: commands)
  }
}
