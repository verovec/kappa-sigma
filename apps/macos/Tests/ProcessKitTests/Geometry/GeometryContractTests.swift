import Metal
import ProcessKit
import Testing

/// `geometry` (card 0090) under the shared contracts: preview = apply, no hidden state, and the
/// crop in full-resolution pixels at scale 2 = half the crop at scale 1.
@Suite("Geometry contracts", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct GeometryContractTests {
  static let cases: [(String, [String: ParamValue])] = [
    ("defaults", [:]),
    (
      "crops + 90° + flip h",
      [
        "cropLeft": .number(4), "cropRight": .number(2), "cropTop": .number(2),
        "rotation": .choice("90"), "flipH": .flag(true),
      ]
    ),
    ("7.5° lanczos expand", ["angle": .number(7.5), "canvas": .choice("expand")]),
    ("−12° bilinear", ["angle": .number(-12), "interpolation": .choice("bilinear")]),
  ]

  @Test("geometry passes every contract, the px-scale rule on each crop at scale 2")
  func testGeometryPasses() throws {
    let contracts = try ProcessContractTests.contracts()
    // The bound (100 000 px) does not fit the 32 × 4 test input: 2 px probes each crop.
    let probes = Dictionary(
      uniqueKeysWithValues: GeometryProcess.schema.pixelParameters.map { ($0, 2.0) })
    #expect(probes.count == 4)
    for (name, values) in Self.cases {
      let params = try GeometryProcessTests.params(values)
      let violations = try contracts.violations(
        of: GeometryProcess.self, params: params, pixelProbes: probes)
      #expect(violations.isEmpty, "\(name): \(violations)")
    }
  }

  @Test("a mask is refused, never blended")
  func testMaskRefused() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let input = try GPUImage(device: device, width: 4, height: 2, channels: 1)
    let mask = try GPUImage(device: device, width: 4, height: 2, channels: 1)
    #expect(throws: ProcessError.self) {
      try ProcessRunner(device: device).run(
        GeometryProcess(params: GeometryProcessTests.params([:]), device: device), input: input,
        stats: LayerStats(channels: []), mask: mask)
    }
  }
}
