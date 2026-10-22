package import Metal

/// One viewer frame on the GPU: the display kernel into the view's texture and the histogram of
/// the region (or the whole image), encoded in one command buffer.
package final class ViewerRenderer {
  /// The device the textures must come from.
  package let device: MTLDevice
  /// The queue every viewer frame is committed to.
  package let queue: MTLCommandQueue
  private let display: DisplayPipeline
  private let histogram: Histogram

  /// A renderer on `device` with RenderKit's shader library.
  package init(device: MTLDevice) throws {
    let library = try ShaderLibrary.load(device: device)
    guard let queue = device.makeCommandQueue() else {
      throw RenderError.commandFailed("command queue")
    }
    self.device = device
    self.queue = queue
    display = try DisplayPipeline(device: device, library: library)
    histogram = try Histogram(device: device, library: library)
  }

  /// Encodes `frame` into `commands`.
  ///
  /// With `histogram`, the returned buffer holds the counts once they complete
  /// (`Histogram.counts`). The histogram depends on the image and `frame.histogramInput` (region,
  /// stride, and the stretch in the display domain) only, so the viewer counts again only when
  /// those change.
  package func encode(
    into commands: MTLCommandBuffer, image: ImageTexture, reference: ImageTexture?,
    frame: ViewerFrame, output: MTLTexture, histogram counting: Bool = true,
    mask: MTLTexture? = nil
  ) throws -> MTLBuffer? {
    try display.encode(
      into: commands, current: image, reference: reference, mask: mask, output: output,
      uniforms: frame.uniforms(for: image))
    guard counting else { return nil }
    let bins = try histogram.makeBins(channels: image.planes.count)
    try histogram.encode(
      into: commands, image: image, stride: frame.histogramStride,
      region: frame.storedRegion(imageHeight: image.height), stf: frame.histogramSTF, bins: bins)
    return bins
  }

  /// Renders `frame` synchronously and returns the histogram (tests, exports).
  package func render(
    image: ImageTexture, reference: ImageTexture?, frame: ViewerFrame, into output: MTLTexture,
    mask: MTLTexture? = nil
  ) throws -> [[Int]] {
    let (_, bins) = try submit(
      image: image, reference: reference, frame: frame, output: output, mask: mask)
    return bins.map { Histogram.counts($0, channels: image.planes.count) } ?? []
  }

  /// Renders `frame` synchronously and returns its GPU time in seconds (frame-budget test).
  package func renderTimed(image: ImageTexture, frame: ViewerFrame, into output: MTLTexture) throws
    -> Double
  {
    let (commands, _) = try submit(image: image, reference: nil, frame: frame, output: output)
    return commands.gpuEndTime - commands.gpuStartTime
  }

  private func submit(
    image: ImageTexture, reference: ImageTexture?, frame: ViewerFrame, output: MTLTexture,
    mask: MTLTexture? = nil
  ) throws -> (MTLCommandBuffer, MTLBuffer?) {
    guard let commands = queue.makeCommandBuffer() else {
      throw RenderError.commandFailed("command buffer")
    }
    let bins = try encode(
      into: commands, image: image, reference: reference, frame: frame, output: output,
      mask: mask)
    commands.commit()
    commands.waitUntilCompleted()
    if let error = commands.error { throw RenderError.commandFailed("\(error)") }
    return (commands, bins)
  }
}
