import Metal
import ProcessKit
import Testing

@Suite("LayerPlane: `R` and `RGB.r` tokens, their textures and their bundle statistics")
struct LayerPlaneTests {
  @Test(
    "a token names a layer and a plane, and spells back the same way",
    arguments: [
      ("R", "R", 0), ("RGB.r", "RGB", 0), ("RGB.g", "RGB", 1), ("RGB.b", "RGB", 2),
      ("Ha", "Ha", 0), ("RGB-dualband.g", "RGB-dualband", 1), ("RGB-dualband.r", "RGB-dualband", 0),
    ])
  func testParsing(token: String, layer: String, plane: Int) {
    let parsed = LayerPlane(token)
    #expect(parsed.layer == layer && parsed.plane == plane)
    #expect(parsed.token == token)
  }

  @Test("the statistics of the named plane, or none")
  func testStats() {
    let channels = (0..<3).map {
      ChannelStats(median: Double($0), madn: 0.1, minimum: 0, maximum: 1)
    }
    let stats = ["RGB": LayerStats(channels: channels)]
    #expect(LayerPlane("RGB.g").stats(in: stats)?.median == 1)
    #expect(LayerPlane("R").stats(in: stats) == nil)
  }

  @Test(
    "a missing layer, a missing plane or another size is refused",
    .enabled(if: MTLCreateSystemDefaultDevice() != nil))
  func testTextureRefusals() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let layers = [
      "R": try GPUImage(device: device, width: 4, height: 2, channels: 1),
      "RGB": try GPUImage(device: device, width: 4, height: 2, channels: 3),
    ]
    #expect(
      try LayerPlane("RGB.b").texture(in: layers, width: 4, height: 2) === layers["RGB"]?.planes[2])
    #expect(throws: ProcessError.missingLayer("G")) {
      try LayerPlane("G").texture(in: layers, width: 4, height: 2)
    }
    #expect(throws: ProcessError.missingLayer("R.g")) {
      try LayerPlane("R.g").texture(in: layers, width: 4, height: 2)
    }
    #expect(throws: ProcessError.sizeMismatch) {
      try LayerPlane("R").texture(in: layers, width: 8, height: 2)
    }
  }
}
