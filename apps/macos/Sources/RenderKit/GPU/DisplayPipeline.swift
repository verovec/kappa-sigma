package import Metal

/// Encodes the `display` kernel: planes (and an optional reference) → an output texture.
package final class DisplayPipeline {
  private let device: MTLDevice
  private let state: MTLComputePipelineState
  private let queue: MTLCommandQueue

  /// A pipeline from `library` (`ShaderLibrary.load`).
  package init(device: MTLDevice, library: MTLLibrary) throws {
    guard let function = library.makeFunction(name: "display") else {
      throw RenderError.missingFunction("display")
    }
    guard let queue = device.makeCommandQueue() else {
      throw RenderError.commandFailed("command queue")
    }
    self.device = device
    self.state = try device.makeComputePipelineState(function: function)
    self.queue = queue
  }

  /// Encodes one frame into `commands`; the output texture's size is the view's.
  package func encode(
    into commands: MTLCommandBuffer, current: ImageTexture, reference: ImageTexture?,
    output: MTLTexture, uniforms: DisplayUniforms
  ) throws {
    guard let encoder = commands.makeComputeCommandEncoder() else {
      throw RenderError.commandFailed("compute encoder")
    }
    let shown = reference ?? current
    encoder.setComputePipelineState(state)
    for (index, texture) in Self.three(current).enumerated() {
      encoder.setTexture(texture, index: index)
    }
    for (index, texture) in Self.three(shown).enumerated() {
      encoder.setTexture(texture, index: 3 + index)
    }
    encoder.setTexture(output, index: 6)
    var values = uniforms
    encoder.setBytes(&values, length: MemoryLayout<DisplayUniforms>.stride, index: 0)
    encoder.dispatchThreads(
      MTLSize(width: output.width, height: output.height, depth: 1),
      threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
    encoder.endEncoding()
  }

  /// Renders one frame synchronously (tests, exports).
  package func render(
    current: ImageTexture, reference: ImageTexture?, into output: MTLTexture,
    uniforms: DisplayUniforms
  ) throws {
    guard let commands = queue.makeCommandBuffer() else {
      throw RenderError.commandFailed("command buffer")
    }
    try encode(
      into: commands, current: current, reference: reference, output: output, uniforms: uniforms)
    commands.commit()
    commands.waitUntilCompleted()
    if let error = commands.error { throw RenderError.commandFailed("\(error)") }
  }

  /// Three texture slots: mono repeats its one plane.
  private static func three(_ image: ImageTexture) -> [MTLTexture] {
    (0..<3).map { image.planes[min($0, image.planes.count - 1)] }
  }
}
