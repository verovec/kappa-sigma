import ImageKit
import Metal
import ProcessKit
import Testing

/// Card 0188: a layer's statistics measured on the GPU are the CPU measure's — the same finite
/// extremes, the same strided sample for the median and MADN — so a chain step reads the same
/// numbers whether its input was read back or stayed on the GPU.
@Suite(
  "GPUStats — the GPU measure equals LayerStats.measured",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct GPUStatsTests {
  /// One image and its name.
  struct Case: CustomTestStringConvertible {
    let name: String
    let width: Int
    let height: Int
    let planes: [[Float]]
    var testDescription: String { name }
    var image: AstroImage {
      AstroImage(
        width: width, height: height, planes: planes, metadata: ImageMetadata(rowOrder: .topDown))
    }
  }

  static func ramp(_ count: Int, offset: Float = 0) -> [Float] {
    (0..<count).map { Float($0) / Float(max(count - 1, 1)) + offset }
  }

  static let cases: [Case] = [
    Case(
      name: "a ramp, three planes", width: 8, height: 8,
      planes: [ramp(64), ramp(64, offset: 0.1), ramp(64, offset: -0.3)]),
    Case(name: "a NaN inside", width: 2, height: 2, planes: [[0.5, .nan, 0.25, 0.75]]),
    Case(
      name: "infinities are not finite", width: 2, height: 2,
      planes: [[-.infinity, 0.5, .infinity, 0.75]]),
    Case(name: "nothing finite", width: 3, height: 1, planes: [[.nan, .infinity, -.infinity]]),
    Case(name: "negatives", width: 2, height: 2, planes: [[-3, -0.5, -7.25, -1]]),
    Case(name: "one pixel", width: 1, height: 1, planes: [[0.125]]),
    Case(name: "odd sizes", width: 3, height: 5, planes: [ramp(15, offset: -0.5)]),
    Case(name: "signed zeros", width: 2, height: 1, planes: [[-0.0, 0.0]]),
  ]

  @Test("testMinMax_MatchesCPU", arguments: cases)
  func testMinMax_MatchesCPU(_ testCase: Case) throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let stats = try GPUStats(device: device)
    let image = testCase.image

    let measured = try stats.measure(GPUImage(device: device, image: image))

    #expect(measured == LayerStats.measured(image))
  }

  /// Above 64 Ki values the median and MADN come from a strided sample: the GPU gathers the same
  /// indices, so the numbers are the CPU's to the bit.
  @Test("testStridedSample_MatchesCPU")
  func testStridedSample_MatchesCPU() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (width, height) = (512, 300)  // 153 600 values: stride 2
    var seed: UInt32 = 12345
    let plane = (0..<(width * height)).map { _ -> Float in
      seed = seed &* 1_664_525 &+ 1_013_904_223
      return Float(seed >> 8) / Float(1 << 24)
    }
    let image = AstroImage(
      width: width, height: height, planes: [plane], metadata: ImageMetadata(rowOrder: .topDown))
    let stats = try GPUStats(device: device)

    let measured = try stats.measure(GPUImage(device: device, image: image))

    let expected = LayerStats.measured(image)
    #expect(measured.channels[0].median == expected.channels[0].median)
    #expect(measured.channels[0].madn == expected.channels[0].madn)
    #expect(measured == expected)
  }
}
