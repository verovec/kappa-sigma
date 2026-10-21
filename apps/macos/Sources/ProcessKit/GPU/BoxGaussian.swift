package import Metal

/// A Gaussian blur as three box passes along x then y.
///
/// Kovesi's box widths, edges clamped: the legacy `imgops.GaussianBlur`, on `Mask.metal`'s box
/// pass.
package struct BoxGaussian {
  private let pipeline: MTLComputePipelineState

  /// The blur's pipeline on `device`.
  package init(device: MTLDevice) throws {
    pipeline = try ProcessLibrary.pipeline(
      device: device, file: "Mask.metal", function: "maskBoxBlur")
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

  /// Encodes `source` blurred by `sigma` pixels into `target`, using `scratch` (all one plane,
  /// one size; `source` is left untouched).
  package func encode(
    _ source: MTLTexture, into target: MTLTexture, scratch: MTLTexture, sigma: Double,
    commands: MTLCommandBuffer
  ) throws {
    let radii = Self.radii(sigma: sigma)
    guard !radii.isEmpty else {
      guard let blit = commands.makeBlitCommandEncoder() else {
        throw ProcessError.commandFailed("blur copy")
      }
      blit.copy(from: source, to: target)
      return blit.endEncoding()
    }
    var input = source
    for radius in radii {
      try pass(input, into: scratch, radius: radius, axis: 0, commands: commands)
      try pass(scratch, into: target, radius: radius, axis: 1, commands: commands)
      input = target
    }
  }

  private func pass(
    _ source: MTLTexture, into target: MTLTexture, radius: Int, axis: Int32,
    commands: MTLCommandBuffer
  ) throws {
    guard let encoder = commands.makeComputeCommandEncoder() else {
      throw ProcessError.commandFailed("blur encoder")
    }
    var radiusAxis = SIMD2(Int32(radius), axis)
    encoder.setComputePipelineState(pipeline)
    encoder.setTexture(source, index: 0)
    encoder.setTexture(target, index: 1)
    unsafe encoder.setBytes(&radiusAxis, length: MemoryLayout<SIMD2<Int32>>.stride, index: 0)
    encoder.dispatchThreads(
      MTLSize(width: target.width, height: target.height, depth: 1),
      threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
    encoder.endEncoding()
  }
}
