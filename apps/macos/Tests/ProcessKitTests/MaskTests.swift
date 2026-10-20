import Metal
import ProcessKit
import Testing

@Suite(
  "Masks: built in the kit, blended in the kit — no process masks itself",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct MaskTests {
  static let width = 32

  static func device() throws -> MTLDevice {
    try #require(MTLCreateSystemDefaultDevice())
  }

  /// 1 on the left half, 0 on the right: a 32×2 step.
  static func halfMask(device: MTLDevice) throws -> GPUImage {
    let row = (0..<width).map { Float($0 < width / 2 ? 1 : 0) }
    return try GPUImage(device: device, width: width, height: 2, planes: [row + row])
  }

  static func ramp(device: MTLDevice, planes: Int = 3) throws -> GPUImage {
    let row = (0..<width).map { Float($0) / Float(width - 1) }
    return try GPUImage(
      device: device, width: width, height: 2, planes: Array(repeating: row + row, count: planes))
  }

  @Test("a process under a half mask changes exactly the masked half; the rest is the input")
  func testGenericBlend() throws {
    let device = try Self.device()
    let input = try Self.ramp(device: device)
    var params = ParamSet(schema: DummyGain.schema)
    try params.set("gain", .number(2))
    let process = try DummyGain(params: params, device: device)
    let runner = try ProcessRunner(device: device)
    let full = try runner.run(process, input: input, stats: LayerStats(channels: [])).read()
    let masked = try runner.run(
      process, input: input, stats: LayerStats(channels: []), mask: Self.halfMask(device: device)
    ).read()
    let original = input.read()
    for plane in 0..<3 {
      for index in 0..<(2 * Self.width) {
        let inside = index % Self.width < Self.width / 2
        #expect(masked[plane][index] == (inside ? full[plane][index] : original[plane][index]))
      }
    }
  }

  @Test(
    "feather turns a hard edge into a monotone ramp of 2·round(r / scale) in-between pixels",
    arguments: [(4.0, 1.0, 8), (4.0, 2.0, 4), (3.0, 1.0, 6), (0.0, 1.0, 0), (4.0, 16.0, 2)])
  func testFeatherRamp(radius: Double, scale: Double, inBetween: Int) throws {
    let device = try Self.device()
    let builder = try MaskBuilder(device: device)
    let feathered = try builder.feather(
      Self.halfMask(device: device), radiusPx: radius, scale: scale)
    let row = Array(feathered.read()[0].prefix(Self.width))
    #expect(zip(row, row.dropFirst()).allSatisfy { $0 >= $1 }, "monotone")
    #expect(row.filter { $0 > 0 && $0 < 1 }.count == inBetween)
    #expect(row.first == 1 && row.last == 0)
  }

  @Test(
    "luminosity range with soft edges equals the CPU oracle; invert complements it to 1",
    arguments: [(0.3, 0.6, 0.1), (0.0, 0.5, 0.0), (0.2, 0.9, 0.25)])
  func testLuminosityRangeSoftEdges(low: Double, high: Double, softness: Double) throws {
    let device = try Self.device()
    let builder = try MaskBuilder(device: device)
    let image = try Self.ramp(device: device)
    let source = MaskSource.luminosityRange(low: low, high: high, softness: softness)
    let mask = try builder.build(Mask(source: source), image: image, scale: 1).read()[0]
    let inverted = try builder.build(Mask(source: source, inverted: true), image: image, scale: 1)
      .read()[0]
    for (index, value) in image.read()[0].enumerated() {
      let luma = Double(value)  // equal planes: Rec. 709 luma = the value
      #expect(abs(Double(mask[index]) - Self.rangeOracle(luma, low, high, softness)) <= 1.0 / 65535)
      #expect(abs(Double(mask[index] + inverted[index]) - 1) <= 1.0 / 65535)
    }
  }

  @Test("the stars proxy marks a point source and leaves flat sky at 0")
  func testStarsProxy() throws {
    let device = try Self.device()
    var plane = [Float](repeating: 0.1, count: 15 * 15)
    plane[7 * 15 + 7] = 0.9
    let image = try GPUImage(device: device, width: 15, height: 15, planes: [plane])
    let mask = try MaskBuilder(device: device).build(
      Mask(source: .stars(threshold: 0.05, radiusPx: 3)), image: image, scale: 1
    ).read()[0]
    #expect(mask[7 * 15 + 7] == 1)
    #expect(mask[0] == 0 && mask[14 * 15 + 14] == 0)
  }

  @Test(
    "a mask that cannot be computed is refused, never NaN",
    arguments: [
      MaskSource.stars(threshold: 0, radiusPx: 3), .stars(threshold: -1, radiusPx: 3),
      .luminosityRange(low: 0.6, high: 0.3, softness: 0),
      .luminosityRange(low: 0, high: 1, softness: -0.1),
    ])
  func testInvalidMasksAreRefused(source: MaskSource) throws {
    let device = try Self.device()
    #expect(throws: ProcessError.self) {
      _ = try MaskBuilder(device: device).build(
        Mask(source: source), image: Self.ramp(device: device), scale: 1)
    }
  }

  /// 1 inside [low, high], linear ramps of width `softness` outside, 0 beyond.
  static func rangeOracle(_ y: Double, _ low: Double, _ high: Double, _ soft: Double) -> Double {
    guard soft > 0 else { return (low...high).contains(y) ? 1 : 0 }
    let rise = min(max((y - (low - soft)) / soft, 0), 1)
    let fall = min(max(((high + soft) - y) / soft, 0), 1)
    return rise * fall
  }
}
