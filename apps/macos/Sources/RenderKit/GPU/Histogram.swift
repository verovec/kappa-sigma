package import Metal

/// The live histogram: 256 bins per channel of the linear values clamped to [0, 1], counted on
/// the GPU at a sampling stride (2 → quarter resolution), over the whole image or a region.
package final class Histogram {
  /// Bins per channel.
  package static let binCount = 256

  private let device: MTLDevice
  private let state: MTLComputePipelineState
  private let queue: MTLCommandQueue

  /// A histogram counter from `library` (`ShaderLibrary.load`).
  package init(device: MTLDevice, library: MTLLibrary) throws {
    guard let function = library.makeFunction(name: "histogram") else {
      throw RenderError.missingFunction("histogram")
    }
    guard let queue = device.makeCommandQueue() else {
      throw RenderError.commandFailed("command queue")
    }
    self.device = device
    self.state = try device.makeComputePipelineState(function: function)
    self.queue = queue
  }

  /// A zeroed bin buffer for `channels` (`encode` adds to it).
  package func makeBins(channels: Int) throws -> MTLBuffer {
    let length = channels * Self.binCount * MemoryLayout<UInt32>.stride
    guard let bins = device.makeBuffer(length: length, options: .storageModeShared) else {
      throw RenderError.commandFailed("histogram bins")
    }
    memset(bins.contents(), 0, length)
    return bins
  }

  /// Encodes the count of `image` (inside `region`, whole image when `nil`) into `bins`: the
  /// linear values, or the displayed ones through `stf` (the display domain, card 0085).
  package func encode(
    into commands: MTLCommandBuffer, image: ImageTexture, stride: Int, region: PixelRegion?,
    stf: [STFParameters]? = nil, bins: MTLBuffer
  ) throws {
    guard let encoder = commands.makeComputeCommandEncoder() else {
      throw RenderError.commandFailed("histogram encoder")
    }
    let area = region ?? PixelRegion(x: 0, y: 0, width: image.width, height: image.height)
    let step = max(stride, 1)
    var uniforms = HistogramUniforms(
      channels: image.planes.count, stride: step, area: area, stf: stf)
    encoder.setComputePipelineState(state)
    for index in 0..<3 {
      encoder.setTexture(image.planes[min(index, image.planes.count - 1)], index: index)
    }
    encoder.setBuffer(bins, offset: 0, index: 0)
    encoder.setBytes(&uniforms, length: MemoryLayout<HistogramUniforms>.stride, index: 1)
    encoder.dispatchThreads(
      MTLSize(
        width: (area.width + step - 1) / step, height: (area.height + step - 1) / step, depth: 1),
      threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
    encoder.endEncoding()
  }

  /// Counts per channel (`bins[c][0..<256]`) of `image`, sampling every `stride` pixels, of the
  /// linear values or of the displayed ones through `stf`.
  package func compute(
    _ image: ImageTexture, stride: Int, region: PixelRegion? = nil, stf: [STFParameters]? = nil
  ) throws -> [[Int]] {
    let bins = try makeBins(channels: image.planes.count)
    guard let commands = queue.makeCommandBuffer() else {
      throw RenderError.commandFailed("histogram")
    }
    try encode(into: commands, image: image, stride: stride, region: region, stf: stf, bins: bins)
    commands.commit()
    commands.waitUntilCompleted()
    if let error = commands.error { throw RenderError.commandFailed("\(error)") }
    return Self.counts(bins, channels: image.planes.count)
  }

  /// The counts held in `bins` for `channels`.
  package static func counts(_ bins: MTLBuffer, channels: Int) -> [[Int]] {
    let counts = bins.contents().bindMemory(to: UInt32.self, capacity: channels * binCount)
    return (0..<channels).map { channel in
      (0..<binCount).map { Int(counts[channel * binCount + $0]) }
    }
  }
}
