import ImageKit
import Metal
import ProcessKit
import Testing

/// Card 0172: what the suggested black points are for, on the kernel itself and a noisy sky.
extension CombinationTests {
  /// A 16×16 mono stack at the M42 skies of card 0170, each master with its own noise, and one
  /// noiseless pixel of a green object.
  enum SkyField {
    static let side = 16
    static let object = 100
    static let skies: [Float] = [0.02322, 0.00860, 0.02423]
    static let sigmas: [Float] = [0.0010, 0.0008, 0.0011]
    static let signal: [Float] = [0.001, 0.016, 0.001]

    /// Plane `channel`: its sky under a bell-shaped noise from a fixed generator.
    static func plane(_ channel: Int) -> [Float] {
      var state = UInt64(channel + 1) &* 0x9E37_79B9_7F4A_7C15
      func uniform() -> Float {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Float(state >> 40) / Float(1 << 24)
      }
      return (0..<(side * side)).map { pixel in
        // The sum of four uniforms: mean 2, standard deviation 1/√3.
        let sum = uniform() + uniform() + uniform() + uniform()
        let noise = (sum - 2) * Float(3).squareRoot()
        return pixel == object
          ? skies[channel] + signal[channel] : skies[channel] + sigmas[channel] * noise
      }
    }

    static func image(_ channel: Int) -> AstroImage {
      AstroImage(
        width: side, height: side, planes: [plane(channel)],
        metadata: ImageMetadata(rowOrder: .topDown))
    }
  }

  /// (max − min) / mean of three values: 0 for a grey.
  static func chroma(_ values: [Float]) -> Float {
    let mean = values.reduce(0, +) / Float(values.count)
    return ((values.max() ?? 0) - (values.min() ?? 0)) / mean
  }

  /// Each channel's mean over the sky pixels of `image`.
  static func skyMeans(_ image: [[Float]]) -> [Float] {
    image.map { plane in
      let sky = plane.enumerated().filter { $0.offset != SkyField.object }.map(\.element)
      return sky.reduce(0, +) / Float(sky.count)
    }
  }

  /// The share of sky pixels with a channel clipped to 0.
  static func clipped(_ image: [[Float]]) -> Double {
    let count = image[0].indices.filter { pixel in
      pixel != SkyField.object && image.contains { $0[pixel] == 0 }
    }.count
    return Double(count) / Double(image[0].count - 1)
  }

  static func combined(
    _ params: ParamSet, layers: [String: GPUImage], device: MTLDevice
  ) throws -> [[Float]] {
    let process = try ChannelCombinationProcess(params: params, device: device)
    let base = try GPUImage(
      device: device, width: SkyField.side, height: SkyField.side, channels: 3)
    return try ProcessRunner(device: device).run(
      process, input: base, stats: LayerStats(channels: []), layers: layers
    ).read()
  }

  @Test(
    """
    the suggested blacks give the channel ratios back to the object: a green object is a grey \
    (chroma < 0.1) at black 0 and green (chroma > 1) with them; the magenta sky (chroma > 0.7) \
    turns near neutral (< 0.4) with under 5 % of it clipped, where blacks at the medians clip \
    over half; GPU = CPU oracle within 1/65535
    """)
  func testSuggestedBlacksRevealTheColour() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let ids = ["R", "G", "B"]
    let images = (0..<3).map(SkyField.image)
    var layers: [String: GPUImage] = [:]
    var stats: [String: LayerStats] = [:]
    for (id, image) in zip(ids, images) {
      layers[id] = try GPUImage(device: device, image: image)
      stats[id] = StudioSession.stats(of: image)
    }
    let plain = try ChannelCombinationProcess.initialParams(planes: ["R": 1, "G": 1, "B": 1])
    var tuned = plain
    var atMedian = plain
    let suggestions = ChannelCombinationProcess.blackSuggestions(plain, layers: stats)
    #expect(suggestions.map(\.paramID) == ["rBlack", "gBlack", "bBlack"])
    for suggestion in suggestions { try tuned.set(suggestion.paramID, suggestion.value) }
    for (id, black) in zip(ids, ["rBlack", "gBlack", "bBlack"]) {
      try atMedian.set(black, .number(try #require(stats[id]?.channels.first).median))
    }

    var rendered: [[[Float]]] = []
    for params in [plain, tuned, atMedian] {
      let out = try Self.combined(params, layers: layers, device: device)
      let blacks = ["rBlack", "gBlack", "bBlack"].map { Float(params.number($0)) }
      let oracle = zip(images, blacks).map { image, black in
        image.planes[0].map { max($0 - black, 0) }
      }
      for (plane, expected) in zip(out, oracle) {
        #expect(zip(plane, expected).allSatisfy { abs($0 - $1) <= 1.0 / 65535 })
      }
      rendered.append(out)
    }
    let object = SkyField.object
    #expect(Self.chroma(rendered[0].map { $0[object] }) < 0.1, "the skies hide the object")
    #expect(Self.chroma(rendered[1].map { $0[object] }) > 1, "the object's own ratios")
    #expect(Self.chroma(Self.skyMeans(rendered[0])) > 0.7, "the raw sky is a magenta cast")
    #expect(Self.chroma(Self.skyMeans(rendered[1])) < 0.4, "what is left is the noise floors")
    #expect(Self.clipped(rendered[1]) < 0.05, "the sky keeps its noise")
    #expect(Self.clipped(rendered[2]) > 0.5, "a black at the median clips most of the sky")
  }
}
