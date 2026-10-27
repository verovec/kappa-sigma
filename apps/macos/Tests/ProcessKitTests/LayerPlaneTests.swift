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
    let averaged = [
      "RGB": LayerStats(channels: [channels[1]]), "R": LayerStats(channels: [channels[2]]),
    ]
    #expect(LayerPlane("RGB.r").stats(in: averaged) == nil, "an average is not the red plane")
    #expect(LayerPlane("R").stats(in: averaged)?.median == 2)
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
    #expect(throws: ProcessError.missingLayer("R.r")) {
      try LayerPlane("R.r").texture(in: layers, width: 4, height: 2)
    }
    // A whole token never reads plane 0 of a colour layer.
    #expect(throws: ProcessError.missingLayer("RGB")) {
      try LayerPlane("RGB").texture(in: layers, width: 4, height: 2)
    }
    #expect(throws: ProcessError.sizeMismatch) {
      try LayerPlane("R").texture(in: layers, width: 8, height: 2)
    }
  }

  /// The tokens a bundle offers a layer parameter (card 0138): `none` first when allowed, the
  /// colour layer first then the canonical filter order, a plane per 3-plane layer, and the
  /// product of every pair of lines present when allowed.
  struct Options: CustomTestStringConvertible, Sendable {
    let name: String
    let layers: [String: Int]
    var allowsNone = false
    var allowsProduct = true
    let expected: [String]
    var testDescription: String { name }
  }

  static let options: [Options] = [
    Options(
      name: "OSC + Hα + OIII, with none", layers: ["RGB": 3, "Ha": 1, "OIII": 1], allowsNone: true,
      expected: ["none", "RGB.r", "RGB.g", "RGB.b", "Ha", "OIII", "Ha*OIII"]),
    Options(
      name: "LRGB", layers: ["L": 1, "R": 1, "G": 1, "B": 1], expected: ["L", "R", "G", "B"]),
    Options(
      name: "SHO", layers: ["SII": 1, "Ha": 1, "OIII": 1],
      expected: ["Ha", "OIII", "SII", "Ha*OIII", "Ha*SII", "OIII*SII"]),
    Options(name: "L only", layers: ["L": 1], expected: ["L"]),
    Options(
      name: "OSC + three lines, products refused",
      layers: ["RGB": 3, "Ha": 1, "OIII": 1, "SII": 1], allowsProduct: false,
      expected: ["RGB.r", "RGB.g", "RGB.b", "Ha", "OIII", "SII"]),
    Options(
      name: "a 3-plane line is offered by plane and makes no product",
      layers: ["Ha": 3, "OIII": 1], expected: ["Ha.r", "Ha.g", "Ha.b", "OIII"]),
    Options(
      name:
        "a custom line sorts after the catalogue and makes its product; a refused id is skipped",
      layers: ["RGB": 3, "NII-custom": 1, "Ha": 1, "Ha*": 1],
      expected: ["RGB.r", "RGB.g", "RGB.b", "Ha", "NII-custom", "Ha*NII-custom"]),
  ]

  @Test("testOptions", arguments: options)
  func testOptions(row: Options) {
    let got = LayerPlane.options(
      planes: row.layers, allowsNone: row.allowsNone, allowsProduct: row.allowsProduct)
    #expect(got == row.expected)
  }
}
