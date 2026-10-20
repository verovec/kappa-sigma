package import Metal

/// Runs a process synchronously.
///
/// One command buffer, waited on: Apply, contracts and tests. The viewer encodes previews into
/// its own frame instead. A mask is applied here, after the process — never inside it.
package struct ProcessRunner {
  private let device: MTLDevice
  private let queue: MTLCommandQueue
  private let blend: MTLComputePipelineState

  /// A runner on `device`.
  package init(device: MTLDevice) throws {
    guard let queue = device.makeCommandQueue() else {
      throw ProcessError.commandFailed("command queue")
    }
    self.device = device
    self.queue = queue
    blend = try ProcessLibrary.pipeline(device: device, file: "Mask.metal", function: "maskBlend")
  }

  /// `process` of `input` at `scale` for `purpose`, into a new image of the same size; under
  /// `mask` (one plane in [0, 1]), out = mask · processed + (1 − mask) · input.
  package func run(
    _ process: any ImageProcess, input: GPUImage, stats: LayerStats, scale: Double = 1,
    purpose: RenderContext.Purpose = .apply, layers: [String: GPUImage] = [:],
    mask: GPUImage? = nil
  ) throws -> GPUImage {
    let processed = try input.sameSize(device: device)
    guard let commands = queue.makeCommandBuffer() else {
      throw ProcessError.commandFailed("command buffer")
    }
    try process.render(
      input, stats: stats, into: processed,
      context: RenderContext(commands: commands, scale: scale, purpose: purpose, layers: layers))
    var output = processed
    if let mask {
      guard mask.width == input.width, mask.height == input.height else {
        throw ProcessError.sizeMismatch
      }
      output = try input.sameSize(device: device)
      try encodeBlend(input: input, processed: processed, mask: mask, into: output, commands)
    }
    commands.commit()
    commands.waitUntilCompleted()
    if let error = commands.error { throw ProcessError.commandFailed("\(error)") }
    return output
  }

  private func encodeBlend(
    input: GPUImage, processed: GPUImage, mask: GPUImage, into output: GPUImage,
    _ commands: MTLCommandBuffer
  ) throws {
    for plane in 0..<output.planes.count {
      guard let encoder = commands.makeComputeCommandEncoder() else {
        throw ProcessError.commandFailed("mask blend encoder")
      }
      encoder.setComputePipelineState(blend)
      encoder.setTexture(input.planes[plane], index: 0)
      encoder.setTexture(processed.planes[plane], index: 1)
      encoder.setTexture(mask.planes[0], index: 2)
      encoder.setTexture(output.planes[plane], index: 3)
      MaskBuilder.dispatch(encoder, over: output)
    }
  }
}
