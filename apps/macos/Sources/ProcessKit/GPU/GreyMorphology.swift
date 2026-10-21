package import Metal

/// Grey erosion, dilation and opening with a square structuring element of side 2·radius + 1, on
/// the GPU (`Morphology.metal`), separable (x then y) and clipped to the image at the edges.
///
/// The opening removes bright structures narrower than the square (point stars) and keeps wider
/// ones (nebulosity): emission screens (0051) and the HDR core mask (0052). `radius` is in working
/// pixels: the caller has already divided its `.px` parameter by the preview scale.
package struct GreyMorphology {
  private let device: MTLDevice
  private let pipeline: MTLComputePipelineState

  /// The morphology kernels on `device`.
  package init(device: MTLDevice) throws {
    self.device = device
    pipeline = try ProcessLibrary.pipeline(
      device: device, file: "Morphology.metal", function: "morphologyWindow")
  }

  /// Encodes the erosion (minimum over the square) of `input` into `output`.
  package func encodeErode(
    _ input: MTLTexture, into output: MTLTexture, radius: Int, commands: MTLCommandBuffer
  ) throws {
    try encode([false], input, into: output, radius: radius, commands: commands)
  }

  /// Encodes the dilation (maximum over the square) of `input` into `output`.
  package func encodeDilate(
    _ input: MTLTexture, into output: MTLTexture, radius: Int, commands: MTLCommandBuffer
  ) throws {
    try encode([true], input, into: output, radius: radius, commands: commands)
  }

  /// Encodes the opening (erosion, then dilation) of `input` into `output`.
  package func encodeOpening(
    _ input: MTLTexture, into output: MTLTexture, radius: Int, commands: MTLCommandBuffer
  ) throws {
    try encode([false, true], input, into: output, radius: radius, commands: commands)
  }

  /// One x pass and one y pass per operation in `dilations`, ping-ponging through two scratch
  /// textures; the last pass writes `output`.
  private func encode(
    _ dilations: [Bool], _ input: MTLTexture, into output: MTLTexture, radius: Int,
    commands: MTLCommandBuffer
  ) throws {
    guard radius >= 0 else { throw ProcessError.invalidParameter("morphology radius \(radius)") }
    guard input.width == output.width, input.height == output.height else {
      throw ProcessError.sizeMismatch
    }
    let scratch = try (0..<2).map { _ in try texture(like: input) }
    let passes = dilations.flatMap { dilation in [(0, dilation), (1, dilation)] }
    var source = input
    for (index, pass) in passes.enumerated() {
      let target = index == passes.count - 1 ? output : scratch[index % 2]
      guard let encoder = commands.makeComputeCommandEncoder() else {
        throw ProcessError.commandFailed("morphology encoder")
      }
      var window = SIMD3(Int32(radius), Int32(pass.0), pass.1 ? 1 : 0)
      encoder.setComputePipelineState(pipeline)
      encoder.setTexture(source, index: 0)
      encoder.setTexture(target, index: 1)
      unsafe encoder.setBytes(&window, length: MemoryLayout<SIMD3<Int32>>.stride, index: 0)
      encoder.dispatchThreads(
        MTLSize(width: target.width, height: target.height, depth: 1),
        threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
      encoder.endEncoding()
      source = target
    }
  }

  private func texture(like input: MTLTexture) throws -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .r32Float, width: input.width, height: input.height, mipmapped: false)
    descriptor.usage = [.shaderRead, .shaderWrite]
    descriptor.storageMode = .private
    guard let texture = device.makeTexture(descriptor: descriptor) else {
      throw ProcessError.commandFailed("morphology texture \(input.width)×\(input.height)")
    }
    return texture
  }
}
