internal import Metal

/// Encodes a `Colour.metal` kernel.
///
/// Input planes at texture 0–2, output planes at 3–5, extra textures from 6, and the uniforms at
/// buffer 0. A mono plane is bound to every slot.
enum ColourKernel {
  /// The pipeline of `function` in `Colour.metal`.
  static func pipeline(device: MTLDevice, function: String) throws -> MTLComputePipelineState {
    try ProcessLibrary.pipeline(device: device, file: "Colour.metal", function: function)
  }

  /// Checks `output` has the size and plane count of `input` (1 or 3 planes).
  static func checkSizes(_ input: GPUImage, _ output: GPUImage) throws {
    let channels = input.planes.count
    guard channels == 1 || channels == 3, output.planes.count == channels,
      output.width == input.width, output.height == input.height
    else { throw ProcessError.sizeMismatch }
  }

  /// Encodes `pipeline` over `output` with `values` and `extra` textures.
  static func encode(
    _ pipeline: MTLComputePipelineState, _ input: GPUImage, into output: GPUImage,
    values: [Float], extra: [MTLTexture] = [], commands: MTLCommandBuffer
  ) throws {
    guard let encoder = commands.makeComputeCommandEncoder() else {
      throw ProcessError.commandFailed("colour encoder")
    }
    var values = values
    let channels = input.planes.count
    encoder.setComputePipelineState(pipeline)
    for slot in 0..<3 {
      encoder.setTexture(input.planes[min(slot, channels - 1)], index: slot)
      encoder.setTexture(output.planes[min(slot, channels - 1)], index: 3 + slot)
    }
    for (offset, texture) in extra.enumerated() { encoder.setTexture(texture, index: 6 + offset) }
    unsafe encoder.setBytes(&values, length: values.count * MemoryLayout<Float>.stride, index: 0)
    encoder.dispatchThreads(
      MTLSize(width: output.width, height: output.height, depth: 1),
      threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
    encoder.endEncoding()
  }

  /// Copies `input` into `output` unchanged (a process with nothing to do on these planes).
  static func copy(_ input: GPUImage, into output: GPUImage, commands: MTLCommandBuffer) throws {
    guard let blit = commands.makeBlitCommandEncoder() else {
      throw ProcessError.commandFailed("colour copy")
    }
    for (source, target) in zip(input.planes, output.planes) {
      blit.copy(from: source, to: target)
    }
    blit.endEncoding()
  }
}
