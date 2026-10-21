package import Metal

/// Successive box blurs on the GPU, one pass per radius along x then y.
///
/// Each pixel is the mean of the edge-clamped window [i − r, i + r] (`Mask.metal`). Up to `directRadius` a thread per
/// pixel sums its window (`maskBoxBlur`); above, a thread per line keeps a Kahan-compensated
/// running sum (`boxBlurRunning`), so the cost stops growing with the radius.
///
/// Three equal passes are astrocomp's `gaussBlur` (emission screens, 0051); three of different
/// widths are hdrcomp's Gaussian (0052); one is a mask feather (0054). Radii are in working pixels:
/// the caller has already divided its `.px` parameter by the preview scale.
package struct BoxBlur {
  private let device: MTLDevice
  private let direct: MTLComputePipelineState
  private let running: MTLComputePipelineState
  /// The largest radius summed per pixel: fewer reads than a serial line walk below it.
  package static let directRadius = 8

  /// The blur kernel on `device`.
  package init(device: MTLDevice) throws {
    self.device = device
    let library = try ProcessLibrary.library(device: device, file: "Mask.metal")
    direct = try ProcessLibrary.pipeline(library: library, function: "maskBoxBlur")
    running = try ProcessLibrary.pipeline(library: library, function: "boxBlurRunning")
  }

  /// Encodes the passes of `radii` (a radius of 0 copies) from `input` into `output`.
  package func encode(
    _ input: MTLTexture, into output: MTLTexture, radii: [Int], commands: MTLCommandBuffer
  ) throws {
    guard radii.allSatisfy({ $0 >= 0 }) else {
      throw ProcessError.invalidParameter("box blur radii \(radii)")
    }
    guard input.width == output.width, input.height == output.height else {
      throw ProcessError.sizeMismatch
    }
    let passes = (radii.isEmpty ? [0] : radii).flatMap { radius in [(radius, 0), (radius, 1)] }
    let scratch = try (0..<min(2, passes.count - 1)).map { _ in
      try ScratchTexture.make(like: input, device: device)
    }
    var source = input
    for (index, pass) in passes.enumerated() {
      let target = index == passes.count - 1 ? output : scratch[index % 2]
      guard let encoder = commands.makeComputeCommandEncoder() else {
        throw ProcessError.commandFailed("box blur encoder")
      }
      var radiusAxis = SIMD2(Int32(pass.0), Int32(pass.1))
      let perLine = pass.0 > Self.directRadius
      encoder.setComputePipelineState(perLine ? running : direct)
      encoder.setTexture(source, index: 0)
      encoder.setTexture(target, index: 1)
      unsafe encoder.setBytes(&radiusAxis, length: MemoryLayout<SIMD2<Int32>>.stride, index: 0)
      if perLine {
        // One thread per row (x pass) or column (y pass).
        let lines = pass.1 == 0 ? target.height : target.width
        encoder.dispatchThreads(
          MTLSize(width: lines, height: 1, depth: 1),
          threadsPerThreadgroup: MTLSize(width: min(64, lines), height: 1, depth: 1))
      } else {
        encoder.dispatchThreads(
          MTLSize(width: target.width, height: target.height, depth: 1),
          threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
      }
      encoder.endEncoding()
      source = target
    }
  }
}
