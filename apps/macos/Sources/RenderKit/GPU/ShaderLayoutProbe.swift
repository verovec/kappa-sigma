package import Metal

/// Pins the Swift mirrors to `ShaderTypes.h`.
///
/// Every field gets a distinct value; the `shaderLayout` kernel reads each one by name and writes
/// its bits back in declaration order, then both `sizeof`s. A field the two sides place
/// differently reads back wrong.
package enum ShaderLayoutProbe {
  /// What the GPU read back and what Swift wrote, in the kernel's order.
  package struct Readout: Equatable {
    /// Words the `shaderLayout` kernel wrote.
    package let gpu: [UInt32]
    /// The same words from the Swift values and `MemoryLayout` sizes.
    package let swift: [UInt32]
  }

  /// Runs the probe on `device` with the library `ShaderLibrary.load` returns.
  package static func run(device: MTLDevice) throws -> Readout {
    var display = sampleDisplay()
    var histogram = sampleHistogram()
    let expected =
      words(display) + words(histogram) + [
        UInt32(MemoryLayout<DisplayUniforms>.size), UInt32(MemoryLayout<HistogramUniforms>.size),
      ]
    let library = try ShaderLibrary.load(device: device)
    guard let function = library.makeFunction(name: "shaderLayout") else {
      throw RenderError.missingFunction("shaderLayout")
    }
    let state = try device.makeComputePipelineState(function: function)
    let length = expected.count * MemoryLayout<UInt32>.stride
    guard let output = device.makeBuffer(length: length, options: .storageModeShared),
      let queue = device.makeCommandQueue(), let commands = queue.makeCommandBuffer(),
      let encoder = commands.makeComputeCommandEncoder()
    else { throw RenderError.commandFailed("layout probe") }
    encoder.setComputePipelineState(state)
    encoder.setBytes(&display, length: MemoryLayout<DisplayUniforms>.stride, index: 0)
    encoder.setBytes(&histogram, length: MemoryLayout<HistogramUniforms>.stride, index: 1)
    encoder.setBuffer(output, offset: 0, index: 2)
    let one = MTLSize(width: 1, height: 1, depth: 1)
    encoder.dispatchThreads(one, threadsPerThreadgroup: one)
    encoder.endEncoding()
    commands.commit()
    commands.waitUntilCompleted()
    if let error = commands.error { throw RenderError.commandFailed("\(error)") }
    let values = output.contents().bindMemory(to: UInt32.self, capacity: expected.count)
    return Readout(gpu: (0..<expected.count).map { values[$0] }, swift: expected)
  }

  /// Distinct values in every field.
  private static func sampleDisplay() -> DisplayUniforms {
    var uniforms = DisplayUniforms(width: 21, height: 22, mipLevels: 23, channels: 13, stf: nil)
    uniforms.shadows = SIMD4(1, 2, 3, 4)
    uniforms.midtone = SIMD4(5, 6, 7, 8)
    uniforms.highlights = SIMD4(9, 10, 11, 12)
    uniforms.stfEnabled = 14
    uniforms.clippingOverlay = 15
    uniforms.compareMode = 16
    uniforms.splitX = 17
    uniforms.scale = 18
    uniforms.originX = 19
    uniforms.originY = 20
    uniforms.flipRows = 24
    uniforms.maskOverlay = 25
    uniforms.canvasGrey = 26
    return uniforms
  }

  /// Distinct values in every field.
  private static func sampleHistogram() -> HistogramUniforms {
    var uniforms = HistogramUniforms(
      channels: 101, stride: 102, area: PixelRegion(x: 103, y: 104, width: 105, height: 106),
      stf: nil)
    uniforms.shadows = SIMD4(31, 32, 33, 34)
    uniforms.midtone = SIMD4(35, 36, 37, 38)
    uniforms.highlights = SIMD4(39, 40, 41, 42)
    uniforms.stfEnabled = 107
    return uniforms
  }

  /// The fields' bits in declaration order.
  private static func words(_ uniforms: HistogramUniforms) -> [UInt32] {
    let lanes = [uniforms.shadows, uniforms.midtone, uniforms.highlights]
      .flatMap { [$0.x, $0.y, $0.z, $0.w] }
    return lanes.map(\.bitPattern) + [
      uniforms.channels, uniforms.stride, uniforms.originX, uniforms.originY, uniforms.width,
      uniforms.height, uniforms.stfEnabled,
    ]
  }

  /// The fields' bits in declaration order.
  private static func words(_ uniforms: DisplayUniforms) -> [UInt32] {
    let lanes = [uniforms.shadows, uniforms.midtone, uniforms.highlights]
      .flatMap { [$0.x, $0.y, $0.z, $0.w] }
    let floats = [
      uniforms.splitX, uniforms.scale, uniforms.originX, uniforms.originY, uniforms.imageWidth,
      uniforms.imageHeight, uniforms.mipLevels,
    ]
    let flags = [
      uniforms.channels, uniforms.stfEnabled, uniforms.clippingOverlay, uniforms.compareMode,
    ]
    return lanes.map(\.bitPattern) + flags + floats.map(\.bitPattern) + [
      uniforms.flipRows, uniforms.maskOverlay, uniforms.canvasGrey.bitPattern,
    ]
  }
}
