import Metal
import ProcessKit
import Testing

@Suite(
  "GreyMorphology: GPU grey erosion, dilation and opening, edge-clipped like astrocomp",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct GreyMorphologyTests {
  static let (width, height) = (37, 23)

  /// A deterministic noise field with a few isolated bright points (stars) and a wide plateau.
  static func field() -> [Float] {
    var state: UInt32 = 0x9E37_79B9
    var plane = (0..<(width * height)).map { _ -> Float in
      state = state &* 1_664_525 &+ 1_013_904_223
      return Float(state >> 8) / Float(1 << 24) * 0.2
    }
    for (x, y) in [(3, 4), (20, 11), (35, 21), (0, 0), (10, 18)] { plane[y * width + x] = 1 }
    for y in 6..<16 { for x in 24..<34 { plane[y * width + x] = 0.7 } }
    return plane
  }

  @Test(
    "van Herk / Gil-Werman equals astrocomp's clipped window on every line",
    arguments: [1, 2, 4, 8, 40])
  func testOracleAgreement(radius: Int) {
    let plane = Self.field()
    for isMax in [false, true] {
      #expect(
        MorphologyOracle.separable(
          plane, width: Self.width, height: Self.height, radius: radius, isMax: isMax,
          MorphologyOracle.vanHerk)
          == MorphologyOracle.separable(
            plane, width: Self.width, height: Self.height, radius: radius, isMax: isMax,
            MorphologyOracle.naive))
    }
  }

  @Test("the GPU opening equals the van Herk oracle, bit for bit", arguments: [0, 1, 4, 8])
  func testOpeningMatchesVanHerk(radius: Int) throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let plane = Self.field()
    let input = try GPUImage(
      device: device, width: Self.width, height: Self.height, planes: [plane])
    let output = try input.sameSize(device: device)
    let queue = try #require(device.makeCommandQueue())
    let commands = try #require(queue.makeCommandBuffer())
    try GreyMorphology(device: device).encodeOpening(
      input.planes[0], into: output.planes[0], radius: radius, commands: commands)
    commands.commit()
    commands.waitUntilCompleted()
    let expected = MorphologyOracle.opening(
      plane, width: Self.width, height: Self.height, radius: radius)
    #expect(output.read()[0] == expected)
  }

  @Test("erosion and dilation alone equal the oracle", arguments: [1, 3])
  func testErodeDilate(radius: Int) throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let plane = Self.field()
    let input = try GPUImage(
      device: device, width: Self.width, height: Self.height, planes: [plane])
    let morphology = try GreyMorphology(device: device)
    let queue = try #require(device.makeCommandQueue())
    for isMax in [false, true] {
      let output = try input.sameSize(device: device)
      let commands = try #require(queue.makeCommandBuffer())
      if isMax {
        try morphology.encodeDilate(
          input.planes[0], into: output.planes[0], radius: radius, commands: commands)
      } else {
        try morphology.encodeErode(
          input.planes[0], into: output.planes[0], radius: radius, commands: commands)
      }
      commands.commit()
      commands.waitUntilCompleted()
      #expect(
        output.read()[0]
          == MorphologyOracle.separable(
            plane, width: Self.width, height: Self.height, radius: radius, isMax: isMax,
            MorphologyOracle.vanHerk))
    }
  }

  @Test("a negative radius is refused")
  func testNegativeRadius() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let image = try GPUImage(device: device, width: 4, height: 4, channels: 1)
    let commands = try #require(device.makeCommandQueue()?.makeCommandBuffer())
    #expect(throws: ProcessError.self) {
      try GreyMorphology(device: device).encodeOpening(
        image.planes[0], into: image.planes[0], radius: -1, commands: commands)
    }
  }
}
