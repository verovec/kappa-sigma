package import Metal

/// Reduces an image to a proxy and brings a reduced result back to full size (card 0189):
/// `Shaders/Resample.metal`, one kernel per plane, each call one command buffer waited on.
package struct Resample {
  private let device: MTLDevice
  private let queue: MTLCommandQueue
  private let box: MTLComputePipelineState
  private let bilinear: MTLComputePipelineState

  /// The kernels on `device`.
  package init(device: MTLDevice) throws {
    guard let queue = device.makeCommandQueue() else {
      throw ProcessError.commandFailed("command queue")
    }
    self.device = device
    self.queue = queue
    let library = try ProcessLibrary.library(device: device, file: "Resample.metal")
    box = try ProcessLibrary.pipeline(library: library, function: "downsampleBox")
    bilinear = try ProcessLibrary.pipeline(library: library, function: "upsampleBilinear")
  }

  /// The image reduced by an integer factor; factor 1 is the image itself.
  ///
  /// Each pixel is the average of the finite values of its factor × factor cell, the last cells
  /// ragged (`FITSFile.downsampled(pooling: .mean)`'s rule).
  package func downsample(_ image: GPUImage, by factor: Int) throws -> GPUImage {
    guard factor > 1 else { return image }
    let output = try GPUImage(
      device: device, width: (image.width + factor - 1) / factor,
      height: (image.height + factor - 1) / factor, channels: image.planes.count)
    var factor = UInt32(factor)
    try run(from: image, to: output, pipeline: box) { encoder in
      unsafe encoder.setBytes(&factor, length: MemoryLayout<UInt32>.stride, index: 0)
    }
    return output
  }

  /// `image` enlarged (or reduced) bilinearly to `width` × `height`; its own size is `image`.
  package func upsample(_ image: GPUImage, toWidth width: Int, toHeight height: Int) throws
    -> GPUImage
  {
    guard width != image.width || height != image.height else { return image }
    let output = try GPUImage(
      device: device, width: width, height: height, channels: image.planes.count)
    try run(from: image, to: output, pipeline: bilinear) { _ in }
    return output
  }

  /// Runs the pipeline over every plane of the source into the target; bind sets its buffers.
  private func run(
    from source: GPUImage, to target: GPUImage, pipeline: MTLComputePipelineState,
    bind: (MTLComputeCommandEncoder) -> Void
  ) throws {
    guard let commands = queue.makeCommandBuffer() else {
      throw ProcessError.commandFailed("command buffer")
    }
    for (input, output) in zip(source.planes, target.planes) {
      guard let encoder = commands.makeComputeCommandEncoder() else {
        throw ProcessError.commandFailed("resample encoder")
      }
      encoder.setComputePipelineState(pipeline)
      encoder.setTexture(input, index: 0)
      encoder.setTexture(output, index: 1)
      bind(encoder)
      encoder.dispatchThreads(
        MTLSize(width: target.width, height: target.height, depth: 1),
        threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
      encoder.endEncoding()
    }
    commands.commit()
    commands.waitUntilCompleted()
    if let error = commands.error { throw ProcessError.commandFailed("\(error)") }
  }
}
