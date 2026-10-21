import Metal
import ProcessKit
import Testing

/// `CurvesProcess`: the monotone spline, its 1024-entry LUT and the shader against the CPU
/// lookup of the same tables.
@Suite("Curves: monotone spline on RGB, R, G, B, luminance and saturation")
struct CurvesTests {
  static let identity = [CurvePoint(0, 0), CurvePoint(1, 1)]
  static let sShape = [
    CurvePoint(0, 0), CurvePoint(0.25, 0.15), CurvePoint(0.5, 0.5), CurvePoint(0.75, 0.88),
    CurvePoint(1, 1),
  ]

  @Test("identity points give the identity; the spline goes through every point")
  func testSplineIdentityAndInterpolation() {
    let identity = MonotoneSpline(Self.identity)
    for x in stride(from: 0.0, through: 1, by: 0.01) { #expect(abs(identity(x) - x) <= 1e-12) }
    let curve = MonotoneSpline(Self.sShape)
    for point in Self.sShape { #expect(abs(curve(point.x) - point.y) <= 1e-12) }
    #expect(curve(-0.5) == 0 && curve(1.5) == 1, "flat outside the points")
  }

  @Test(
    "monotone control points give a monotone curve, without overshoot",
    arguments: [
      sShape,
      [CurvePoint(0, 0), CurvePoint(0.1, 0.6), CurvePoint(0.12, 0.62), CurvePoint(1, 1)],
      [CurvePoint(0, 0.2), CurvePoint(0.4, 0.2), CurvePoint(0.6, 0.9), CurvePoint(1, 0.9)],
      [CurvePoint(0, 1), CurvePoint(0.5, 0.3), CurvePoint(1, 0)],
    ])
  func testSplineMonotone(points: [CurvePoint]) {
    let curve = MonotoneSpline(points)
    let samples = stride(from: 0.0, through: 1, by: 1.0 / 4096).map { curve($0) }
    let ys = points.map(\.y)
    let rising = ys[ys.count - 1] >= ys[0]
    for (left, right) in zip(samples, samples.dropFirst()) {
      #expect(rising ? right >= left - 1e-12 : right <= left + 1e-12)
    }
    let (low, high) = (ys.min() ?? 0, ys.max() ?? 1)
    #expect(samples.allSatisfy { $0 >= low - 1e-12 && $0 <= high + 1e-12 })
  }

  @Test("the LUT samples the spline at i / 1023")
  func testLUTSamples() {
    let lut = MonotoneSpline(Self.sShape).lut()
    #expect(lut.count == CurvesProcess.lutSize)
    for index in [0, 100, 511, 1023] {
      #expect(abs(Double(lut[index]) - MonotoneSpline(Self.sShape)(Double(index) / 1023)) < 1e-7)
    }
  }

  @Test(
    "the shader equals the CPU lookup of the same LUTs, and only the chosen curve moves",
    .enabled(if: MTLCreateSystemDefaultDevice() != nil),
    arguments: ["rgb", "red", "green", "blue", "luminance", "saturation"])
  func testSplineMonotoneAndIdentity(curve: String) throws {
    let field = ColourFixtures.field()
    #expect(try ColourFixtures.run(CurvesProcess.self, [:], planes: field) == field)
    let out = try ColourFixtures.run(
      CurvesProcess.self, [curve: .points(Self.sShape)], planes: field)
    let lut = MonotoneSpline(Self.sShape).lut()
    let expected = ColourFixtures.map(field) { CurvesOracle.apply($0, curve: curve, lut: lut) }
    #expect(ColourFixtures.maxDifference(out, expected) <= 1.0 / 65535)
    let moved = (0..<3).filter { out[$0] != field[$0] }
    switch curve {
    case "red": #expect(moved == [0])
    case "green": #expect(moved == [1])
    case "blue": #expect(moved == [2])
    default: #expect(moved == [0, 1, 2])
    }
  }

  @Test(
    "a mono image takes the RGB and luminance curves only",
    .enabled(if: MTLCreateSystemDefaultDevice() != nil))
  func testMono() throws {
    let plane = [ColourFixtures.field()[0]]
    let lut = MonotoneSpline(Self.sShape).lut()
    for curve in ["rgb", "luminance"] {
      let out = try ColourFixtures.run(
        CurvesProcess.self, [curve: .points(Self.sShape)], planes: plane)
      let expected = [plane[0].map { CurvesOracle.lookup(lut, $0) }]
      #expect(ColourFixtures.maxDifference(out, expected) <= 1.0 / 65535)
    }
    for curve in ["red", "saturation"] {
      #expect(
        try ColourFixtures.run(CurvesProcess.self, [curve: .points(Self.sShape)], planes: plane)
          == plane)
    }
  }
}

/// The CPU side of `Curves.metal`'s lookup.
enum CurvesOracle {
  /// `lut` at `x`, linear between entries, `x` clamped into [0, 1].
  static func lookup(_ lut: [Float], _ x: Float) -> Float {
    let position = min(max(x, 0), 1) * Float(lut.count - 1)
    let index = min(Int(position), lut.count - 2)
    let frac = position - Float(index)
    return lut[index] + (lut[index + 1] - lut[index]) * frac
  }

  /// One pixel with `lut` as the curve `curve` and the identity for the others.
  static func apply(_ rgb: [Float], curve: String, lut: [Float]) -> [Float] {
    switch curve {
    case "rgb": return rgb.map { lookup(lut, $0) }
    case "red": return [lookup(lut, rgb[0]), rgb[1], rgb[2]]
    case "green": return [rgb[0], lookup(lut, rgb[1]), rgb[2]]
    case "blue": return [rgb[0], rgb[1], lookup(lut, rgb[2])]
    case "luminance":
      let luma = 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]
      let lift = lookup(lut, luma) - luma
      return rgb.map { min(max($0 + lift, 0), 1) }
    default:
      let (mx, mn) = (max(rgb[0], rgb[1], rgb[2]), min(rgb[0], rgb[1], rgb[2]))
      guard mx != mn else { return rgb }
      let light = (mx + mn) / 2
      let sat = light <= 0.5 ? (mx - mn) / (mx + mn) : (mx - mn) / (2 - mx - mn)
      let hue = ColourOracle.hue(rgb[0], rgb[1], rgb[2], mx: mx, mn: mn)
      let (r, g, b) = ColourOracle.hslToRGB(hue, lookup(lut, sat), light)
      return [r, g, b]
    }
  }
}
