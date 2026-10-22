package import Metal

/// Runs a process synchronously.
///
/// One command buffer, waited on: Apply, contracts and tests. A live preview encodes the same
/// `render` and `MaskBlend` into its own frame. A mask is applied after the process — never
/// inside it.
package struct ProcessRunner {
  let device: MTLDevice
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

  /// `process` of `input` at `scale` for `purpose`, into a new image.
  ///
  /// The image has the input's size (a `GeometricProcess`'s own size) and the process's plane
  /// count; under `mask`, out = mask · processed + (1 − mask) · input. `rowsBottomUp`: the
  /// input's stored row order.
  package func run(
    _ process: any ImageProcess, input: GPUImage, stats: LayerStats, scale: Double = 1,
    purpose: RenderContext.Purpose = .apply, layers: [String: GPUImage] = [:],
    layerStats: [String: LayerStats] = [:],
    mask: GPUImage? = nil, rowsBottomUp: Bool = false
  ) throws -> GPUImage {
    let channels = type(of: process).outputChannels(input: input.planes.count)
    var size = (width: input.width, height: input.height)
    if let geometric = process as? any GeometricProcess {
      // A moved grid has no input pixel under each output pixel to blend with.
      guard mask == nil else {
        throw ProcessError.invalidParameter("geometry applies to the whole image, never a mask")
      }
      size = try geometric.outputSize(
        width: input.width, height: input.height, scale: scale, bottomUp: rowsBottomUp)
    }
    let processed = try GPUImage(
      device: device, width: size.width, height: size.height, channels: channels)
    guard let commands = queue.makeCommandBuffer() else {
      throw ProcessError.commandFailed("command buffer")
    }
    try process.render(
      input, stats: stats, into: processed,
      context: RenderContext(
        commands: commands, scale: scale, purpose: purpose, layers: layers, layerStats: layerStats,
        rowsBottomUp: rowsBottomUp))
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
