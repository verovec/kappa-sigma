package import Metal

/// Runs a process synchronously.
///
/// One command buffer, waited on: Apply, contracts and tests. A live preview encodes the same
/// `render` and `MaskBlend` into its own frame. A mask is applied after the process — never
/// inside it.
package struct ProcessRunner {
  private let device: MTLDevice
  private let queue: MTLCommandQueue
  private let blend: MaskBlend

  /// A runner on `device`.
  package init(device: MTLDevice) throws {
    guard let queue = device.makeCommandQueue() else {
      throw ProcessError.commandFailed("command queue")
    }
    self.device = device
    self.queue = queue
    blend = try MaskBlend(device: device)
  }

  /// `process` of `input` at `scale` for `purpose`, into a new image of the input's size (and the
  /// process's plane count); under `mask`, out = mask · processed + (1 − mask) · input.
  package func run(
    _ process: any ImageProcess, input: GPUImage, stats: LayerStats, scale: Double = 1,
    purpose: RenderContext.Purpose = .apply, layers: [String: GPUImage] = [:],
    layerStats: [String: LayerStats] = [:],
    mask: GPUImage? = nil
  ) throws -> GPUImage {
    let channels = type(of: process).outputChannels(input: input.planes.count)
    let processed = try GPUImage(
      device: device, width: input.width, height: input.height, channels: channels)
    guard let commands = queue.makeCommandBuffer() else {
      throw ProcessError.commandFailed("command buffer")
    }
    try process.render(
      input, stats: stats, into: processed,
      context: RenderContext(
        commands: commands, scale: scale, purpose: purpose, layers: layers, layerStats: layerStats))
    var output = processed
    if let mask {
      output = try processed.sameSize(device: device)
      try blend.encode(
        into: commands, input: input, processed: processed, mask: mask, output: output)
    }
    commands.commit()
    commands.waitUntilCompleted()
    if let error = commands.error { throw ProcessError.commandFailed("\(error)") }
    return output
  }
}
