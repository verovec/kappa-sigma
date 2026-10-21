import Metal
import ProcessKit
import Testing

/// Writes the bundle median of its `Ha` layer (`RenderContext.layerStats`) into every pixel: the
/// smallest process reading a layer's statistics instead of measuring it.
struct LayerMedianFill: ImageProcess {
  static let id = "layer-median-fill"
  static let title = "Layer median fill"
  static let stage = ProcessStage.any
  static let schema = ParamSchema([])
  static let previewExactOnlyAt1to1 = false
  let params: ParamSet
  init(params: ParamSet, device: MTLDevice) throws { self.params = params }

  func render(
    _ input: GPUImage, stats: LayerStats, into output: GPUImage, context: RenderContext
  ) throws {
    guard let median = context.layerStats["Ha"]?.channels.first?.median else {
      throw ProcessError.missingLayer("Ha")
    }
    let values = [Float](repeating: Float(median), count: output.width * output.height)
    for plane in output.planes {
      unsafe values.withUnsafeBytes { bytes in
        guard let base = bytes.baseAddress else { return }
        unsafe plane.replace(
          region: MTLRegionMake2D(0, 0, output.width, output.height), mipmapLevel: 0,
          withBytes: base, bytesPerRow: output.width * MemoryLayout<Float>.stride)
      }
    }
  }
}

@Suite(
  "Layer statistics reach a process through the render context and the suggestions",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct LayerStatsSeamTests {
  static let ha = LayerStats(
    channels: [ChannelStats(median: 0.25, madn: 0.01, minimum: 0, maximum: 1)], continuumK: 0.4,
    continuumReference: "RGB.r")

  @Test("ProcessRunner hands the bundle statistics of each layer to render")
  func testRunnerPassesLayerStats() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let input = try GPUImage(device: device, width: 4, height: 2, channels: 1)
    let process = try LayerMedianFill(
      params: ParamSet(schema: LayerMedianFill.schema), device: device)
    let output = try ProcessRunner(device: device).run(
      process, input: input, stats: LayerStats(channels: []), layerStats: ["Ha": Self.ha])
    #expect(output.read()[0].allSatisfy { $0 == 0.25 })
    #expect(throws: ProcessError.missingLayer("Ha")) {
      try ProcessRunner(device: device).run(process, input: input, stats: LayerStats(channels: []))
    }
  }

  @Test("a process without layer suggestions gives those of its input statistics")
  func testDefaultLayerSuggestions() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let process = try DummyGain(params: ProcessContractTests.gain(), device: device)
    let stats = LayerStats(channels: [
      ChannelStats(median: 0.05, madn: 0.001, minimum: 0, maximum: 1)
    ])
    #expect(
      process.suggestions(stats: stats, layers: ["Ha": Self.ha])
        == process.suggestions(stats: stats))
  }
}
