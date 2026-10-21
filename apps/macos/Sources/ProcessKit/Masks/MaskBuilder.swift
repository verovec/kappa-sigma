package import Metal

/// Computes masks on the GPU (`Mask.metal`) for the image a process runs on.
package struct MaskBuilder {
  private let device: MTLDevice
  private let queue: MTLCommandQueue
  private let rangePipeline: MTLComputePipelineState
  private let starsPipeline: MTLComputePipelineState
  private let blur: BoxBlur

  /// A builder on `device`.
  package init(device: MTLDevice) throws {
    guard let queue = device.makeCommandQueue() else {
      throw ProcessError.commandFailed("command queue")
    }
    self.device = device
    self.queue = queue
    let library = try ProcessLibrary.library(device: device, file: "Mask.metal")
    rangePipeline = try ProcessLibrary.pipeline(library: library, function: "maskLuminosityRange")
    starsPipeline = try ProcessLibrary.pipeline(library: library, function: "maskStars")
    blur = try BoxBlur(device: device)
  }

  /// `mask` of `image` at `scale` (full-resolution pixels per working pixel): one plane in [0, 1].
  package func build(_ mask: Mask, image: GPUImage, scale: Double) throws -> GPUImage {
    if let problem = mask.source.problem { throw ProcessError.invalidParameter(problem) }
    guard mask.featherPx.isFinite, mask.featherPx >= 0 else {
      throw ProcessError.invalidParameter("feather \(mask.featherPx) px")
    }
    let output = try GPUImage(device: device, width: image.width, height: image.height, channels: 1)
    let channels = Float(image.planes.count)
    let invert: Float = mask.inverted ? 1 : 0
    switch mask.source {
    case .luminosityRange(let low, let high, let softness):
      try run(
        rangePipeline, image: image, into: output,
        values: [Float(low), Float(high), Float(softness), invert, channels])
    case .stars(let threshold, let radiusPx):
      let radius = Self.workingRadius(radiusPx, scale: scale)
      try run(
        starsPipeline, image: image, into: output,
        values: [Float(threshold), Float(radius), invert, channels])
    }
    return try feather(output, radiusPx: mask.featherPx, scale: scale)
  }

  /// `mask` box-blurred by `radiusPx / scale` (rounded) along x then y: a hard edge becomes a
  /// monotone linear ramp with 2·radius in-between pixels.
  package func feather(_ mask: GPUImage, radiusPx: Double, scale: Double) throws -> GPUImage {
    let radius = Self.workingRadius(radiusPx, scale: scale)
    guard radius > 0 else { return mask }
    let feathered = try GPUImage(
      device: device, width: mask.width, height: mask.height, channels: 1)
    guard let commands = queue.makeCommandBuffer() else {
      throw ProcessError.commandFailed("feather")
    }
    try blur.encode(mask.planes[0], into: feathered.planes[0], radii: [radius], commands: commands)
    try Self.finish(commands)
    return feathered
  }

  /// A pixel radius at the working scale: rounded, and at least 1 when `radiusPx` is not 0, so a
  /// coarse preview level keeps the mask Apply will use instead of collapsing it.
  static func workingRadius(_ radiusPx: Double, scale: Double) -> Int {
    guard radiusPx > 0 else { return 0 }
    return max(1, Int((radiusPx / max(scale, 1e-9)).rounded()))
  }

  private func run(
    _ pipeline: MTLComputePipelineState, image: GPUImage, into output: GPUImage, values: [Float]
  ) throws {
    guard let commands = queue.makeCommandBuffer(),
      let encoder = commands.makeComputeCommandEncoder()
    else { throw ProcessError.commandFailed("mask") }
    var values = values
    encoder.setComputePipelineState(pipeline)
    for index in 0..<3 {
      encoder.setTexture(image.planes[min(index, image.planes.count - 1)], index: index)
    }
    encoder.setTexture(output.planes[0], index: 3)
    unsafe encoder.setBytes(&values, length: values.count * MemoryLayout<Float>.stride, index: 0)
    Self.dispatch(encoder, over: output)
    try Self.finish(commands)
  }

  static func dispatch(_ encoder: MTLComputeCommandEncoder, over image: GPUImage) {
    encoder.dispatchThreads(
      MTLSize(width: image.width, height: image.height, depth: 1),
      threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
    encoder.endEncoding()
  }

  static func finish(_ commands: MTLCommandBuffer) throws {
    commands.commit()
    commands.waitUntilCompleted()
    if let error = commands.error { throw ProcessError.commandFailed("\(error)") }
  }
}
