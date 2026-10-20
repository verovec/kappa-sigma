package import Metal

/// Runs a process synchronously.
///
/// One command buffer, waited on: Apply, contracts and tests. The viewer encodes previews into
/// its own frame instead.
package struct ProcessRunner {
  private let device: MTLDevice
  private let queue: MTLCommandQueue

  /// A runner on `device`.
  package init(device: MTLDevice) throws {
    guard let queue = device.makeCommandQueue() else {
      throw ProcessError.commandFailed("command queue")
    }
    self.device = device
    self.queue = queue
  }

  /// `process` of `input` at `scale` for `purpose`, into a new image of the same size.
  package func run(
    _ process: any ImageProcess, input: GPUImage, stats: LayerStats, scale: Double = 1,
    purpose: RenderContext.Purpose = .apply
  ) throws -> GPUImage {
    let output = try input.sameSize(device: device)
    guard let commands = queue.makeCommandBuffer() else {
      throw ProcessError.commandFailed("command buffer")
    }
    try process.render(
      input, stats: stats, into: output,
      context: RenderContext(commands: commands, scale: scale, purpose: purpose))
    commands.commit()
    commands.waitUntilCompleted()
    if let error = commands.error { throw ProcessError.commandFailed("\(error)") }
    return output
  }
}
