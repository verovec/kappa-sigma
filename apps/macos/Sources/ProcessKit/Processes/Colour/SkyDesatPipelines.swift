internal import Metal

/// The sky-desat passes (`SkyDesat.metal` + `BoxGaussian`), encoded into one command buffer.
struct SkyDesatPipelines {
  private let mean: MTLComputePipelineState
  private let starWeight: MTLComputePipelineState
  private let residual: MTLComputePipelineState
  private let desat: MTLComputePipelineState
  private let gaussian: BoxGaussian

  init(device: MTLDevice) throws {
    let library = try ProcessLibrary.library(device: device, file: "SkyDesat.metal")
    mean = try ProcessLibrary.pipeline(library: library, function: "skyMean")
    starWeight = try ProcessLibrary.pipeline(library: library, function: "skyStarWeight")
    residual = try ProcessLibrary.pipeline(library: library, function: "skyResidual")
    desat = try ProcessLibrary.pipeline(library: library, function: "skyDesat")
    gaussian = try BoxGaussian(device: device)
  }

  /// mean → its star-detail and coarse blurs → star weight → each channel's star-masked residual
  /// blurred to the coarse field → the two stages.
  func encode(
    _ input: GPUImage, into output: GPUImage, uniforms: SkyDesatUniforms,
    commands: MTLCommandBuffer
  ) throws {
    let plane = { try Self.intermediate(like: input, device: commands.device) }
    let (meanPlane, scratch, detail, coarse, weight) = (
      try plane(), try plane(), try plane(), try plane(), try plane()
    )
    try run(mean, input.planes + [meanPlane], over: output, commands: commands)
    try gaussian.encode(
      meanPlane, into: detail, scratch: scratch, sigma: uniforms.starSigma, commands: commands)
    try gaussian.encode(
      meanPlane, into: coarse, scratch: scratch, sigma: uniforms.coarseSigma, commands: commands)
    try run(
      starWeight, [detail, coarse, weight], values: uniforms.star, over: output, commands: commands)
    var fields: [MTLTexture] = []
    // The star-detail plane is free once the weight is drawn: it holds each channel's residual.
    let masked = detail
    for channel in input.planes {
      let field = try plane()
      try run(residual, [channel, meanPlane, weight, masked], over: output, commands: commands)
      try gaussian.encode(
        masked, into: field, scratch: scratch, sigma: uniforms.coarseSigma, commands: commands)
      fields.append(field)
    }
    try run(
      desat, input.planes + output.planes + [meanPlane, coarse, weight] + fields,
      values: uniforms.final, over: output, commands: commands)
  }

  /// A GPU-only plane the size of `image`.
  ///
  /// `.private`: no CPU copy, never read back.
  private static func intermediate(like image: GPUImage, device: MTLDevice) throws -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .r32Float, width: image.width, height: image.height, mipmapped: false)
    descriptor.usage = [.shaderRead, .shaderWrite]
    descriptor.storageMode = .private
    guard let texture = device.makeTexture(descriptor: descriptor) else {
      throw ProcessError.commandFailed("sky desat plane")
    }
    return texture
  }

  private func run(
    _ pipeline: MTLComputePipelineState, _ textures: [MTLTexture], values: [Float] = [],
    over image: GPUImage, commands: MTLCommandBuffer
  ) throws {
    guard let encoder = commands.makeComputeCommandEncoder() else {
      throw ProcessError.commandFailed("sky desat encoder")
    }
    encoder.setComputePipelineState(pipeline)
    for (index, texture) in textures.enumerated() { encoder.setTexture(texture, index: index) }
    if !values.isEmpty {
      var values = values
      unsafe encoder.setBytes(&values, length: values.count * MemoryLayout<Float>.stride, index: 0)
    }
    encoder.dispatchThreads(
      MTLSize(width: image.width, height: image.height, depth: 1),
      threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
    encoder.endEncoding()
  }
}
