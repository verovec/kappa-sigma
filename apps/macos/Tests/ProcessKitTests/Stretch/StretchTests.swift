import Metal
import ProcessKit
import Testing

/// `StretchProcess`: the shader against `StretchOracle` on ramps and noise fields.
@Suite("Stretch: MTF, GHS and asinh, with the headroom cap", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct StretchTests {
  static let width = 64
  static let height = 4

  /// A ramp over [−0.05, 1.05] (rows 0–1) and a deterministic noise field (rows 2–3), per plane.
  static func planes(_ count: Int) -> [[Float]] {
    var seed: UInt32 = 12_345
    return (0..<count).map { plane in
      (0..<width * height).map { index in
        let (row, column) = (index / width, index % width)
        if row < 2 {
          return -0.05 + 1.1 * Float(column) / Float(width - 1) * (1 - 0.1 * Float(plane))
        }
        seed = seed &* 1_664_525 &+ 1_013_904_223
        return 0.02 + 0.2 * Float(seed % 10_000) / 10_000
      }
    }
  }

  static let stats = LayerStats(channels: [
    ChannelStats(median: 0.040, madn: 0.006, minimum: 0, maximum: 1),
    ChannelStats(median: 0.050, madn: 0.008, minimum: 0, maximum: 1),
    ChannelStats(median: 0.030, madn: 0.004, minimum: 0, maximum: 1),
  ])

  static func run(_ values: [String: ParamValue], planes: [[Float]]) throws -> [[Float]] {
    let device = try #require(MTLCreateSystemDefaultDevice())
    var params = ParamSet(schema: StretchProcess.schema)
    for (id, value) in values { try params.set(id, value) }
    let input = try GPUImage(device: device, width: width, height: height, planes: planes)
    let process = try StretchProcess(params: params, device: device)
    let stats = LayerStats(channels: Array(Self.stats.channels.prefix(planes.count)))
    return try ProcessRunner(device: device).run(process, input: input, stats: stats).read()
  }

  /// The oracle's output for every pixel, `stretch` mapping a (headroom-capped) pixel.
  static func expected(_ planes: [[Float]], ceiling: Double, stretch: ([Double]) -> [Double])
    -> [[Float]]
  {
    var out = planes.map { _ in [Float](repeating: 0, count: width * height) }
    for index in 0..<width * height {
      let pixel = StretchOracle.headroom(planes.map { Double($0[index]) }, ceiling: ceiling)
      for (plane, value) in stretch(pixel).enumerated() { out[plane][index] = Float(value) }
    }
    return out
  }

  static func maxDifference(_ lhs: [[Float]], _ rhs: [[Float]]) -> Float {
    zip(lhs.joined(), rhs.joined()).map { abs($0 - $1) }.max() ?? .infinity
  }

  struct MTFCase: CustomTestStringConvertible, Sendable {
    let clip: Double
    let target: Double
    let linked: Bool
    let planes: Int
    var testDescription: String { "clip \(clip)σ bg \(target) linked \(linked) ×\(planes)" }
  }

  @Test(
    "MTF from the bundle stats equals the CPU oracle within 1/65535",
    arguments: [
      MTFCase(clip: -2.8, target: 0.25, linked: true, planes: 3),
      MTFCase(clip: -2.8, target: 0.25, linked: false, planes: 3),
      MTFCase(clip: -1.5, target: 0.15, linked: false, planes: 3),
      MTFCase(clip: 0, target: 0.4, linked: true, planes: 1),
    ])
  func testMTFMatchesCPUOracle(_ example: MTFCase) throws {
    let planes = Self.planes(example.planes)
    let out = try Self.run(
      [
        "mode": .choice("mtf"), "shadowsClip": .number(example.clip),
        "targetBackground": .number(example.target), "linked": .flag(example.linked),
      ], planes: planes)
    let channels = Array(Self.stats.channels.prefix(example.planes))
    let parameters: [(shadows: Double, midtone: Double)] =
      example.linked
      ? Array(
        repeating: StretchOracle.autostretch(
          median: channels.map(\.median).reduce(0, +) / Double(channels.count),
          madn: channels.map(\.madn).reduce(0, +) / Double(channels.count), clip: example.clip,
          target: example.target), count: channels.count)
      : channels.map {
        StretchOracle.autostretch(
          median: $0.median, madn: $0.madn, clip: example.clip, target: example.target)
      }
    let expected = Self.expected(planes, ceiling: 1) { pixel in
      pixel.enumerated().map {
        StretchOracle.stretchMTF(
          $1, shadows: parameters[$0].shadows, midtone: parameters[$0].midtone)
      }
    }
    #expect(Self.maxDifference(out, expected) <= 1.0 / 65535)
  }

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
    "asinh equals the ratio-preserving reference within 1e-5 (β = 0 is a black-point lift)",
    arguments: zip([0.0, 10, 150, 500, 50], [0.0, 0.0, 0.01, 0.03, 0.2]))
  func testAsinhMatchesReference(beta: Double, black: Double) throws {
    for count in [1, 3] {
      let planes = Self.planes(count)
      let out = try Self.run(
        ["mode": .choice("asinh"), "asinhStretch": .number(beta), "asinhBlack": .number(black)],
        planes: planes)
      let expected = Self.expected(planes, ceiling: 1) {
        StretchOracle.asinhStretch($0, beta: beta, black: black)
      }
      #expect(Self.maxDifference(out, expected) <= 1e-5, "\(count) plane(s)")
    }
  }

  @Test("GHS refuses protection points on the wrong side of the symmetry point")
  func testGHSOrdering() throws {
    #expect(throws: ProcessError.self) {
      _ = try Self.run(
        ["mode": .choice("ghs"), "ghsStretch": .number(2), "ghsSymmetry": .number(0.1),
         "ghsShadows": .number(0.3)], planes: Self.planes(1))
    }
  }

  @Test("headroom keeps each pixel's RGB ratios to 1e-5, is monotone and stays under the ceiling")
  func testHeadroomMonotoneRatioPreserving() throws {
    // Bright linear cores up to 2× the white point; hues whose channels stay under 1 at the ceiling.
    let planes: [[Float]] = [1.0, 0.9, 0.8].map { hue in
      (0..<Self.width * Self.height).map { Float(hue) * 2 * Float($0) / Float(Self.width * Self.height) }
    }
    // GHS at D = 0 is the identity: what comes out is the headroom stage alone.
    let out = try Self.run(
      ["mode": .choice("ghs"), "ghsStretch": .number(0), "headroom": .number(0.9)], planes: planes)
    let expected = Self.expected(planes, ceiling: 0.9) { $0 }
    #expect(Self.maxDifference(out, expected) <= 1e-6)
    for index in 0..<Self.width * Self.height where planes[0][index] > 0 {
      #expect(abs(out[1][index] / out[0][index] - 0.9) <= 1e-5)
      #expect(abs(out[2][index] / out[0][index] - 0.8) <= 1e-5)
    }
    let luma = (0..<Self.width * Self.height).map {
      0.299 * out[0][$0] + 0.587 * out[1][$0] + 0.114 * out[2][$0]
    }
    // float32: near the tanh asymptote the recomputed luminance moves by an ulp (1e-6).
    #expect(zip(luma, luma.dropFirst()).allSatisfy { $0 <= $1 + 1e-6 })
    #expect((luma.max() ?? 1) <= 0.9 + 1e-6)
  }
}
