internal import ImageKit
internal import Metal

extension DenoiseProcess {
  /// One starlet smoothing at dilation `step`: rows into `row`, then columns into `target`.
  func smooth(
    _ source: MTLTexture, into target: MTLTexture, step: Int32, row: MTLTexture,
    commands: MTLCommandBuffer
  ) throws {
    for (axis, from, to) in [(Int32(0), source, row), (1, row, target)] {
      guard let encoder = commands.makeComputeCommandEncoder() else {
        throw ProcessError.commandFailed("denoise encoder")
      }
      var stepAxis = SIMD2(step, axis)
      encoder.setComputePipelineState(pass)
      encoder.setTexture(from, index: 0)
      encoder.setTexture(to, index: 1)
      unsafe encoder.setBytes(&stepAxis, length: MemoryLayout<SIMD2<Int32>>.stride, index: 0)
      Self.dispatch(encoder, size: to)
    }
  }

  /// The share of each pixel kept, from the scale-2 smooth, the plane's median and the noise σ.
  func encodeProtection(
    _ scaleTwo: MTLTexture, into mask: MTLTexture, median: Double, sigma: Double,
    commands: MTLCommandBuffer
  ) throws {
    let band = StarletNoise.protection
    var values = [Float(median), Float(sigma), Float(band.low), Float(band.high)]
    try dispatch(protect, [scaleTwo, mask], &values, size: mask, commands: commands)
  }

  /// The shares of the luminance and colour changes put back on an image of `planes` planes.
  ///
  /// A mono plane has no colour. What the blend reads and what decides a render is a copy.
  func blendWeights(planes: Int) -> (luminance: Double, colour: Double) {
    let amount = params.number("amount")
    let colour = planes == 3 ? amount * params.number("chrominance") : 0
    return (amount * params.number("luminance"), colour)
  }

  /// The denoised planes in `output` moved back toward `input` by `blendWeights`.
  func encodeBlend(_ input: GPUImage, into output: GPUImage, commands: MTLCommandBuffer) throws {
    let planes = (0..<3).map { min($0, input.planes.count - 1) }
    let weights = blendWeights(planes: input.planes.count)
    var values = [Float(weights.luminance), Float(weights.colour), Float(input.planes.count)]
    try dispatch(
      blend, planes.map { input.planes[$0] } + planes.map { output.planes[$0] }, &values,
      size: output.planes[0], commands: commands)
  }

  /// `input` copied into `output`, bit for bit (amount 0).
  func copy(_ input: GPUImage, into output: GPUImage, commands: MTLCommandBuffer) throws {
    guard let blit = commands.makeBlitCommandEncoder() else {
      throw ProcessError.commandFailed("denoise copy encoder")
    }
    for (source, target) in zip(input.planes, output.planes) {
      blit.copy(from: source, to: target)
    }
    blit.endEncoding()
  }

  /// `pipeline` over every pixel of `size`, `textures` in order, `values` at buffer 0.
  func dispatch(
    _ pipeline: MTLComputePipelineState, _ textures: [MTLTexture], _ values: inout [Float],
    size: MTLTexture, commands: MTLCommandBuffer
  ) throws {
    guard let encoder = commands.makeComputeCommandEncoder() else {
      throw ProcessError.commandFailed("denoise encoder")
    }
    encoder.setComputePipelineState(pipeline)
    for (index, texture) in textures.enumerated() { encoder.setTexture(texture, index: index) }
    if !values.isEmpty {
      unsafe encoder.setBytes(&values, length: values.count * MemoryLayout<Float>.stride, index: 0)
    }
    Self.dispatch(encoder, size: size)
  }

  private static func dispatch(_ encoder: MTLComputeCommandEncoder, size: MTLTexture) {
    encoder.dispatchThreads(
      MTLSize(width: size.width, height: size.height, depth: 1),
      threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
    encoder.endEncoding()
  }
}
