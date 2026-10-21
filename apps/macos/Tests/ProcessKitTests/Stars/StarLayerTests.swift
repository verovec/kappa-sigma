import Metal
import ProcessKit
import Testing

/// stardesat's per-pixel math in double, written from its `main.go` (not from the kernel).
enum StarLayerOracle {
  static func recompose(
    original: [Double], starless: [Double], chroma: Double, presence: Double, screen: Bool = false
  ) -> [Double] {
    let stars = zip(original, starless).map { max($0 - $1, 0) }
    let luma = 0.2126 * stars[0] + 0.7152 * stars[1] + 0.0722 * stars[2]
    return zip(stars, starless).map { star, base in
      let layer = presence * (luma + (star - luma) * chroma)
      let out = screen ? 1 - (1 - base) * (1 - min(max(layer, 0), 1)) : base + layer
      return min(max(out, 0), 1)
    }
  }
}

@Suite(
  "Star layer: stardesat's recomposition — chroma around the luma, presence, additive or screen",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct StarLayerTests {
  static let width = 8

  /// Original: a red star over a grey starless on the left half; a pixel StarNet brightened
  /// (starless > original) on the right.
  static func images() -> (original: [[Float]], starless: [[Float]]) {
    let starless: [[Float]] = [0.20, 0.22, 0.25].map { Array(repeating: $0, count: width) }
    var original = starless
    for x in 0..<(width / 2) {
      original[0][x] += 0.5
      original[1][x] += 0.2 + Float(x) * 0.01
      original[2][x] += 0.05
    }
    for x in (width / 2)..<width { original[1][x] -= 0.1 }
    return (original, starless)
  }

  static func render(chroma: Double, presence: Double, mode: String) throws -> [[Float]] {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (original, starless) = Self.images()
    var params = ParamSet(schema: StarRecompositionProcess.schema)
    try params.set("chroma", .number(chroma))
    try params.set("presence", .number(presence))
    try params.set("mode", .choice(mode))
    let input = try GPUImage(device: device, width: width, height: 1, planes: original)
    let layer = try GPUImage(device: device, width: width, height: 1, planes: starless)
    return try ProcessRunner(device: device).run(
      StarRecompositionProcess(params: params, device: device), input: input,
      stats: LayerStats(channels: []), layers: ["starless": layer]
    ).read()
  }

  @Test(
    "equals stardesat within 1/65535 (k, r, mode)",
    arguments: [
      (0.0, 1.0, "additive"), (0.25, 0.25, "additive"), (0.25, 0.75, "additive"),
      (1.0, 1.0, "additive"), (0.5, 0.5, "screen"), (1.0, 1.0, "screen"),
    ])
  func testRecompose(chroma: Double, presence: Double, mode: String) throws {
    let out = try Self.render(chroma: chroma, presence: presence, mode: mode)
    let (original, starless) = Self.images()
    for x in 0..<Self.width {
      let expected = StarLayerOracle.recompose(
        original: original.map { Double($0[x]) }, starless: starless.map { Double($0[x]) },
        chroma: chroma, presence: presence, screen: mode == "screen")
      for channel in 0..<3 {
        #expect(abs(Double(out[channel][x]) - expected[channel]) <= 1.0 / 65535)
      }
    }
  }

  @Test("k = 0 gives grey stars, k = 1 the original; where StarNet brightened, the starless stays")
  func testChromaEnds() throws {
    let (original, starless) = Self.images()
    let grey = try Self.render(chroma: 0, presence: 1, mode: "additive")
    let full = try Self.render(chroma: 1, presence: 1, mode: "additive")
    for x in 0..<(Self.width / 2) {
      let added = (0..<3).map { grey[$0][x] - starless[$0][x] }
      #expect(abs(added[0] - added[1]) <= 1e-6 && abs(added[1] - added[2]) <= 1e-6)
      for channel in 0..<3 { #expect(abs(full[channel][x] - original[channel][x]) <= 1e-6) }
    }
    for x in (Self.width / 2)..<Self.width {
      for channel in 0..<3 { #expect(abs(full[channel][x] - starless[channel][x]) <= 1e-6) }
    }
  }

  @Test("without the starless layer the process is refused, never run on another layer")
  func testMissingStarless() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let input = try GPUImage(device: device, width: 2, height: 1, channels: 3)
    #expect(throws: ProcessError.missingLayer("starless")) {
      try ProcessRunner(device: device).run(
        StarRecompositionProcess(
          params: ParamSet(schema: StarRecompositionProcess.schema), device: device),
        input: input, stats: LayerStats(channels: []))
    }
  }

  @Test("passes every contract with its starless layer, under a mask")
  func testContracts() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (original, starless) = Self.images()
    let contracts = try ProcessContracts(
      device: device,
      input: GPUImage(device: device, width: Self.width, height: 1, planes: original),
      stats: LayerStats(channels: []),
      layers: ["starless": GPUImage(device: device, width: Self.width, height: 1, planes: starless)]
    )
    var params = ParamSet(schema: StarRecompositionProcess.schema)
    try params.set("chroma", .number(0.25))
    try params.set("presence", .number(0.75))
    #expect(try contracts.violations(of: StarRecompositionProcess.self, params: params).isEmpty)
  }
}
