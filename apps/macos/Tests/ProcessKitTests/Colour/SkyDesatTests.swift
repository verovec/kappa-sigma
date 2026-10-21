import Metal
import ProcessKit
import Testing

/// `SkyDesatProcess`: the shader against `SkyDesatOracle`, and the IC 1848 lesson — the colour of
/// an extended nebula survives while the sky's mottle goes.
@Suite(
  "Sky desaturation: brightness-relative masks, keep-cool, extended nebula",
  .enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct SkyDesatTests {
  static let (width, height) = (160, 48)
  static let sky: Float = 0.05
  static let patch: Float = 4e-5

  /// Sky with warm mottle (x < 50), a faint veil with blue patches (50 ≤ x < 100, +0.5 % of the
  /// sky), an extended emission nebula with R/G = 2 (x ≥ 100, +20 %), and a saturated star.
  static func field() -> [[Float]] {
    var planes = [[Float]](repeating: [Float](repeating: 0, count: width * height), count: 3)
    for y in 0..<height {
      for x in 0..<width {
        let index = y * width + x
        let checker = ((x / 6) + (y / 6)) % 2 == 0
        var (r, g, b) = (sky, sky, sky)
        if x < 50 {
          let warm = checker ? patch : -patch
          (r, b) = (r + warm, b - warm)
        } else if x < 100 {
          let lift = sky * 0.005
          (r, g, b) = (r + lift, g + lift, b + lift)
          if checker { (r, b) = (r - patch, b + patch) }
        } else {
          (r, g, b) = (r + 0.02, g + 0.01, b + 0.01)
        }
        planes[0][index] = r
        planes[1][index] = g
        planes[2][index] = b
      }
    }
    for plane in 0..<3 { planes[plane][20 * width + 30] = 0.95 }
    return planes
  }

  static let stats = LayerStats(
    channels: Array(
      repeating: ChannelStats(median: Double(sky), madn: 2e-5, minimum: 0, maximum: 1), count: 3))
  static var sigmaC: Double { 2e-5 * (2.0 / 3).squareRoot() }

  static func run(_ values: [String: ParamValue]) throws -> [[Float]] {
    try ColourFixtures.run(
      SkyDesatProcess.self, values.merging(["scalePx": .number(12)]) { given, _ in given },
      planes: field(), width: width, stats: stats)
  }

  /// Mean |chroma| (each channel minus the pixel mean) over columns `columns`, rows 6–41.
  static func chroma(
    _ planes: [[Float]], columns: Range<Int>, where keep: (Int, Int) -> Bool = { _, _ in true }
  )
    -> Double
  {
    var (sum, count) = (0.0, 0)
    for y in 6..<42 {
      for x in columns where keep(x, y) {
        let index = y * width + x
        let mean = (planes[0][index] + planes[1][index] + planes[2][index]) / 3
        sum += Double(abs(planes[0][index] - mean) + abs(planes[2][index] - mean))
        count += 1
      }
    }
    return sum / Double(count)
  }

  @Test(
    "the shader equals the CPU port of chromasmooth's sky desat within 2e-7",
    arguments: zip([1.0, 0.5, 1.0], [false, false, true]))
  func testMatchesOracle(strength: Double, keepCool: Bool) throws {
    let out = try Self.run(["strength": .number(strength), "keepCool": .flag(keepCool)])
    var options = SkyDesatOracle.Options()
    (options.strength, options.keepCool, options.scalePx) = (strength, keepCool, 12)
    let expected = SkyDesatOracle.apply(
      Self.field(), width: Self.width, height: Self.height, sky: Double(Self.sky),
      sigmaC: Self.sigmaC, options)
    #expect(ColourFixtures.maxDifference(out, expected) <= 2e-7)
  }

  @Test("an extended nebula keeps its R/G ratio within 2 % while the sky mottle drops ≥ 80 %")
  func testExtendedNebulaKeepsRatio() throws {
    let field = Self.field()
    let out = try Self.run(["strength": .number(1)])
    for y in 6..<42 {
      for x in 120..<160 {
        let index = y * Self.width + x
        let (before, after) = (field[0][index] / field[1][index], out[0][index] / out[1][index])
        #expect(abs(after / before - 1) <= 0.02)
      }
    }
    let (mottle, left) = (Self.chroma(field, columns: 8..<42), Self.chroma(out, columns: 8..<42))
    #expect(left <= 0.2 * mottle, "sky chroma \(mottle) → \(left)")
  }

  @Test("keep-cool preserves the blue veil that the plain pass flattens")
  func testKeepCoolPreservesBlueVeil() throws {
    let field = Self.field()
    let blue: (Int, Int) -> Bool = { x, y in ((x / 6) + (y / 6)) % 2 == 0 }
    let veil = Self.chroma(field, columns: 62..<88, where: blue)
    let cool = Self.chroma(
      try Self.run(["strength": .number(1), "keepCool": .flag(true)]), columns: 62..<88, where: blue
    )
    let plain = Self.chroma(try Self.run(["strength": .number(1)]), columns: 62..<88, where: blue)
    #expect(cool >= 0.9 * veil, "keep-cool: \(veil) → \(cool)")
    #expect(plain <= 0.6 * veil, "plain: \(veil) → \(plain)")
  }

  @Test("strength 0 is the identity bit for bit; a mono image passes through")
  func testIdentity() throws {
    #expect(try Self.run([:]) == Self.field())
    let mono = [Self.field()[0]]
    #expect(
      try ColourFixtures.run(
        SkyDesatProcess.self, ["strength": .number(1)], planes: mono, width: Self.width,
        stats: Self.stats) == mono)
  }

  @Test("no bundle sky level, or crossed bands, is refused with the reason")
  func testRefusals() throws {
    #expect(throws: ProcessError.self) {
      try ColourFixtures.run(
        SkyDesatProcess.self, ["strength": .number(1)], planes: Self.field(), width: Self.width)
    }
    #expect(throws: ProcessError.self) {
      try Self.run(["strength": .number(1), "nebulaLow": .number(0.2), "nebulaHigh": .number(0.1)])
    }
  }
}
