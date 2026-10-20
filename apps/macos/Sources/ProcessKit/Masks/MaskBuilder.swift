package import Metal

/// Computes masks on the GPU (`Mask.metal`) for the image a process runs on.
package struct MaskBuilder {
  private let device: MTLDevice
  private let queue: MTLCommandQueue
  private let rangePipeline: MTLComputePipelineState
  private let starsPipeline: MTLComputePipelineState
  private let blurPipeline: MTLComputePipelineState

  /// A builder on `device`.
  package init(device: MTLDevice) throws {
    guard let queue = device.makeCommandQueue() else {
      throw ProcessError.commandFailed("command queue")
    }
    self.device = device
    self.queue = queue
    rangePipeline = try ProcessLibrary.pipeline(
      device: device, file: "Mask.metal", function: "maskLuminosityRange")
    starsPipeline = try ProcessLibrary.pipeline(
      device: device, file: "Mask.metal", function: "maskStars")
    blurPipeline = try ProcessLibrary.pipeline(
      device: device, file: "Mask.metal", function: "maskBoxBlur")
  }

  /// `mask` of `image` at `scale` (full-resolution pixels per working pixel): one plane in [0, 1].
  package func build(_ mask: Mask, image: GPUImage, scale: Double) throws -> GPUImage {
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
    let across = try GPUImage(device: device, width: mask.width, height: mask.height, channels: 1)
    let both = try GPUImage(device: device, width: mask.width, height: mask.height, channels: 1)
    guard let commands = queue.makeCommandBuffer() else {
      throw ProcessError.commandFailed("feather")
    }
    for (axis, source, target) in [(Int32(0), mask, across), (1, across, both)] {
      guard let encoder = commands.makeComputeCommandEncoder() else {
        throw ProcessError.commandFailed("feather encoder")
      }
      var radiusAxis = SIMD2(Int32(radius), axis)
      encoder.setComputePipelineState(blurPipeline)
      encoder.setTexture(source.planes[0], index: 0)
      encoder.setTexture(target.planes[0], index: 1)
      unsafe encoder.setBytes(&radiusAxis, length: MemoryLayout<SIMD2<Int32>>.stride, index: 0)
      Self.dispatch(encoder, over: target)
    }
    try Self.finish(commands)
    return both
  }

  /// A pixel radius at the working scale.
  static func workingRadius(_ radiusPx: Double, scale: Double) -> Int {
    max(0, Int((radiusPx / max(scale, 1e-9)).rounded()))
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
