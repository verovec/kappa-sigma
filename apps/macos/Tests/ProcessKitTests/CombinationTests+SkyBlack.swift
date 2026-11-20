import Metal
import ProcessKit
import Testing

/// Card 0172: what the suggested black points are for, on the kernel itself.
extension CombinationTests {
  /// (max − min) / mean of one pixel's R, G, B: 0 for a grey.
  static func chroma(_ image: [[Float]], pixel: Int) -> Float {
    let values = image.map { $0[pixel] }
    let mean = values.reduce(0, +) / Float(values.count)
    return ((values.max() ?? 0) - (values.min() ?? 0)) / mean
  }

  /// The median of `plane`, as the bundle records a layer's sky.
  static func median(_ plane: [Float]) -> Double {
    let sorted = plane.sorted()
    return Double(sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
  }

  @Test(
    """
    the suggested blacks give the channel ratios back to the object: on the M42 skies of card \
    0170 a green object is a grey (chroma < 0.1) at black 0 and green (chroma > 2) with them, \
    and the magenta sky (chroma > 0.7) becomes 0; GPU = CPU oracle within 1/65535
    """)
  func testSuggestedBlacksRevealTheColour() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let object = 5
    let skies: [Float] = [0.02322, 0.00860, 0.02423]
    let signal: [Float] = [0.001, 0.016, 0.001]
    let planes: [[Float]] = zip(skies, signal).map { sky, signal in
      (0..<8).map { $0 == object ? sky + signal : sky }
    }
    var layers: [String: GPUImage] = [:]
    var stats: [String: LayerStats] = [:]
    for (id, plane) in zip(["R", "G", "B"], planes) {
      layers[id] = try GPUImage(device: device, width: 4, height: 2, planes: [plane])
      stats[id] = LayerStats(
        channels: [
          ChannelStats(median: Self.median(plane), madn: 0, minimum: 0, maximum: 1)
        ])
    }
    let plain = try ChannelCombinationProcess.initialParams(planes: ["R": 1, "G": 1, "B": 1])
    var tuned = plain
    let suggestions = ChannelCombinationProcess.blackSuggestions(plain, layers: stats)
    #expect(suggestions.map(\.paramID) == ["rBlack", "gBlack", "bBlack"])
    for suggestion in suggestions { try tuned.set(suggestion.paramID, suggestion.value) }

    for (params, blacks) in [(plain, [0, 0, 0]), (tuned, skies)] {
      let out = try Self.render(params, layers: layers, device: device)
      let oracle = zip(planes, blacks).map { plane, black in plane.map { max($0 - black, 0) } }
      for (rendered, expected) in zip(out, oracle) {
        #expect(zip(rendered, expected).allSatisfy { abs($0 - $1) <= 1.0 / 65535 })
      }
    }
    let before = try Self.render(plain, layers: layers, device: device)
    let after = try Self.render(tuned, layers: layers, device: device)
    #expect(Self.chroma(before, pixel: object) < 0.1, "the sky offsets hide the object's colour")
    #expect(Self.chroma(after, pixel: object) > 2, "the object's own ratios")
    #expect(Self.chroma(before, pixel: 0) > 0.7, "the unsubtracted sky is a magenta cast")
    #expect(after.allSatisfy { $0[0] == 0 }, "the sky is neutral: 0 in every channel")
  }
}
