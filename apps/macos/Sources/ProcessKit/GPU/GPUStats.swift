package import Metal
internal import RenderKit

/// A layer's statistics measured on the GPU (card 0188): the numbers `LayerStats.measured` gives,
/// without reading the plane back — the finite extremes reduced by the `extremes` kernel, the
/// median and MADN computed on the CPU from the same strided sample `AutoSTF` takes.
///
/// A class: it keeps the buffers its kernels write between two measures (a chain step measures
/// its input and every moved layer on each drag frame).
package final class GPUStats {
  private let device: MTLDevice
  private let queue: MTLCommandQueue
  private let extremes: MTLComputePipelineState
  private let sampler: MTLComputePipelineState
  /// The buffers of the last measure, reused while the sample count stays the same.
  private var pool: (samples: Int, pairs: [(bounds: MTLBuffer, sample: MTLBuffer)]) = (0, [])

  /// The key of a value no finite value is above / below: what an empty plane leaves.
  private static let noMinimum = UInt32.max
  private static let noMaximum: UInt32 = 0

  /// The kernels on `device`.
  package init(device: MTLDevice) throws {
    guard let queue = device.makeCommandQueue() else {
      throw ProcessError.commandFailed("command queue")
    }
    self.device = device
    self.queue = queue
    let library = try ProcessLibrary.library(device: device, file: "Stats.metal")
    extremes = try ProcessLibrary.pipeline(library: library, function: "extremes")
    sampler = try ProcessLibrary.pipeline(library: library, function: "sampleStrided")
  }

  /// The statistics of `image`, one command buffer for every plane, waited on.
  package func measure(_ image: GPUImage) throws -> LayerStats {
    let count = image.width * image.height
    let stride = AutoSTF.sampleStride(count: count)
    let samples = (count + stride - 1) / stride
    guard let commands = queue.makeCommandBuffer() else {
      throw ProcessError.commandFailed("command buffer")
    }
    var pairs: [(bounds: MTLBuffer, sample: MTLBuffer)] = []
    for (index, plane) in image.planes.enumerated() {
      let pair = try buffers(at: index, samples: samples)
      try encode(
        plane, into: commands, bounds: pair.bounds, sample: pair.sample, stride: UInt32(stride),
        count: UInt32(samples))
      pairs.append(pair)
    }
    commands.commit()
    commands.waitUntilCompleted()
    if let error = commands.error { throw ProcessError.commandFailed("\(error)") }
    return LayerStats(channels: pairs.map { Self.channel($0.bounds, $0.sample, count: samples) })
  }

  /// The buffers of plane `index` for `samples` values, from the pool when it holds them, with
  /// the bounds reset to « nothing finite yet ».
  private func buffers(at index: Int, samples: Int) throws -> (bounds: MTLBuffer, sample: MTLBuffer)
  {
    if pool.samples != samples { pool = (samples, []) }
    if index >= pool.pairs.count {
      guard
        let bounds = device.makeBuffer(
          length: 2 * MemoryLayout<UInt32>.stride, options: .storageModeShared),
        let sample = device.makeBuffer(
          length: max(samples, 1) * MemoryLayout<Float>.stride, options: .storageModeShared)
      else { throw ProcessError.commandFailed("statistics buffers") }
      pool.pairs.append((bounds, sample))
    }
    let pair = pool.pairs[index]
    unsafe pair.bounds.contents().storeBytes(of: Self.noMinimum, as: UInt32.self)
    unsafe pair.bounds.contents().storeBytes(
      of: Self.noMaximum, toByteOffset: MemoryLayout<UInt32>.stride, as: UInt32.self)
    return pair
  }

  private func encode(
    _ plane: MTLTexture, into commands: MTLCommandBuffer, bounds: MTLBuffer, sample: MTLBuffer,
    stride: UInt32, count: UInt32
  ) throws {
    guard let encoder = commands.makeComputeCommandEncoder() else {
      throw ProcessError.commandFailed("statistics encoder")
    }
    defer { encoder.endEncoding() }
    encoder.setComputePipelineState(extremes)
    encoder.setTexture(plane, index: 0)
    encoder.setBuffer(bounds, offset: 0, index: 0)
    encoder.dispatchThreads(
      MTLSize(width: plane.width, height: plane.height, depth: 1),
      threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
    var stride = stride
    var count = count
    encoder.setComputePipelineState(sampler)
    encoder.setTexture(plane, index: 0)
    encoder.setBuffer(sample, offset: 0, index: 0)
    unsafe encoder.setBytes(&stride, length: MemoryLayout<UInt32>.stride, index: 1)
    unsafe encoder.setBytes(&count, length: MemoryLayout<UInt32>.stride, index: 2)
    let perGroup = min(sampler.maxTotalThreadsPerThreadgroup, 256)
    encoder.dispatchThreads(
      MTLSize(width: Int(count), height: 1, depth: 1),
      threadsPerThreadgroup: MTLSize(width: perGroup, height: 1, depth: 1))
  }

  /// One plane's statistics from what its kernels wrote.
  private static func channel(_ bounds: MTLBuffer, _ sample: MTLBuffer, count: Int)
    -> ChannelStats
  {
    let minKey = unsafe bounds.contents().load(as: UInt32.self)
    let maxKey = unsafe bounds.contents().load(
      fromByteOffset: MemoryLayout<UInt32>.stride, as: UInt32.self)
    let values = unsafe Array(
      UnsafeBufferPointer(
        start: sample.contents().assumingMemoryBound(to: Float.self), count: count))
    let (median, madn) = AutoSTF.sampleMedianAndMADN(values)
    guard minKey != noMinimum else {
      return ChannelStats(median: median, madn: madn, minimum: 0, maximum: 0)
    }
    return ChannelStats(
      median: median, madn: madn, minimum: Double(value(of: minKey)),
      maximum: Double(value(of: maxKey)))
  }

  /// The float whose ordered key is `key` (the kernel's `orderedKey`, inverted).
  static func value(of key: UInt32) -> Float {
    let bits = key & 0x8000_0000 != 0 ? key & 0x7FFF_FFFF : ~key
    return Float(bitPattern: bits)
  }
}
