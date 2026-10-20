import Metal
import ProcessKit
import Testing

/// GHS: the shader against the reference equations, and the reference against its own
/// mathematical properties.
extension StretchTests {
  struct GHSCase: CustomTestStringConvertible, Sendable {
    let stretch: Double
    let b: Double
    let sp: Double
    let lp: Double
    let hp: Double
    var testDescription: String { "ln(D+1) \(stretch) b \(b) SP \(sp) LP \(lp) HP \(hp)" }
  }

  @Test(
    "GHS equals the reference equations within 1e-5, for every family of b",
    arguments: [
      GHSCase(stretch: 3, b: 0, sp: 0.05, lp: 0, hp: 1),
      GHSCase(stretch: 3, b: 2, sp: 0.05, lp: 0, hp: 1),
      GHSCase(stretch: 5, b: 8, sp: 0.04, lp: 0.01, hp: 0.9),
      GHSCase(stretch: 2, b: -1, sp: 0.1, lp: 0, hp: 1),
      GHSCase(stretch: 2, b: -0.5, sp: 0.2, lp: 0.05, hp: 0.8),
      GHSCase(stretch: 1, b: -3, sp: 0, lp: 0, hp: 0.95),
      // Next to the logarithmic family: (b + 1) / b is tiny and float cancellation shows.
      GHSCase(stretch: 4, b: -0.999, sp: 0.05, lp: 0, hp: 1),
      GHSCase(stretch: 4, b: -1.001, sp: 0.05, lp: 0, hp: 1),
      GHSCase(stretch: 6, b: 0.001, sp: 0.02, lp: 0, hp: 1),
      GHSCase(stretch: 0, b: 4, sp: 0.1, lp: 0, hp: 1),
    ])
  func testGHSMatchesReference(_ example: GHSCase) throws {
    let planes = Self.planes(3)
    let out = try Self.run(
      [
        "mode": .choice("ghs"), "ghsStretch": .number(example.stretch),
        "ghsIntensity": .number(example.b), "ghsSymmetry": .number(example.sp),
        "ghsShadows": .number(example.lp), "ghsHighlights": .number(example.hp),
      ], planes: planes)
    let expected = Self.expected(planes, ceiling: 1) { pixel in
      pixel.map {
        StretchOracle.ghs(
          $0, stretch: example.stretch, b: example.b, lp: example.lp, sp: example.sp,
          hp: example.hp)
      }
    }
    #expect(Self.maxDifference(out, expected) <= 1e-5)
  }

  @Test(
    """
    the GHS reference is self-consistent: T(0) = 0, T′ > 0 and equal to dT/dx, and the families \
    meet (b → 0 is exponential, b → −1 logarithmic)
    """,
    arguments: [-3.0, -1, -0.5, 0, 2, 8])
  func testGHSReferenceProperties(b: Double) {
    for strength in [1.7, 20.0] {
      #expect(StretchOracle.base(0, b: b, strength: strength).value == 0)
      for x in stride(from: 0.01, through: 0.99, by: 0.07) {
        let step = 1e-6
        let point = StretchOracle.base(x, b: b, strength: strength)
        let numeric =
          (StretchOracle.base(x + step, b: b, strength: strength).value
            - StretchOracle.base(x - step, b: b, strength: strength).value) / (2 * step)
        #expect(point.slope > 0 && abs(numeric - point.slope) <= 1e-5 * max(1, point.slope))
      }
    }
    // The families meet in shape, T(x) / T(1): the b < 0 family carries a 1/D the logarithm does
    // not, a constant the stretch's normalisation cancels.
    func shape(_ x: Double, _ b: Double) -> Double {
      StretchOracle.base(x, b: b, strength: 5).value
        / StretchOracle.base(1, b: b, strength: 5).value
    }
    for x in [0.05, 0.3, 0.9] {
      #expect(abs(shape(x, 1e-7) - shape(x, 0)) <= 1e-5)
      #expect(abs(shape(x, -1 + 1e-7) - shape(x, -1)) <= 1e-5)
      #expect(abs(shape(x, -1 - 1e-7) - shape(x, -1)) <= 1e-5)
    }
  }

  @Test("GHS refuses protection points on the wrong side of the symmetry point")
  func testGHSOrdering() throws {
    #expect(throws: ProcessError.self) {
      _ = try Self.run(
        [
          "mode": .choice("ghs"), "ghsStretch": .number(2), "ghsSymmetry": .number(0.1),
          "ghsShadows": .number(0.3),
        ], planes: Self.planes(1))
    }
  }

  @Test(
    "an MTF whose shadows reach the median (clip 0, or MADN 0) is refused, not a threshold",
    arguments: [(0.0, 0.006), (-2.8, 0.0)])
  func testMTFRefusesADegenerateMidtone(clip: Double, madn: Double) throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    var params = ParamSet(schema: StretchProcess.schema)
    try params.set("shadowsClip", .number(clip))
    let input = try GPUImage(
      device: device, width: Self.width, height: Self.height, planes: Self.planes(1))
    let stats = LayerStats(channels: [
      ChannelStats(median: 0.04, madn: madn, minimum: 0, maximum: 1)
    ])
    #expect(throws: ProcessError.self) {
      _ = try ProcessRunner(device: device).run(
        try StretchProcess(params: params, device: device), input: input, stats: stats)
    }
  }
}
