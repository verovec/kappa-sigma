import Foundation
import StackKit
import Testing

/// `CurveFit` is `photom.FitCurves`: cases translated from `internal/photom/fit_test.go`, with
/// its tolerances (1e-9 for exact recoveries, 1% for the robust ones).
@Suite("CurveFit — the affine map of one night's tonal curve onto the reference's")
struct CurveFitTests {
  /// Sky-dominated: 85% near-pedestal pixels with a mild spread, a 15% signal ramp tail.
  static func skyCurve(_ count: Int = 10_000) -> FrameCurve {
    let pixels = (0..<count).map { index -> Float in
      index % 100 < 85
        ? 0.05 + 0.004 * Float(index % 17) / 17 : 0.05 + 0.95 * Float(index) / Float(count - 1)
    }
    return FrameCurve(planes: [pixels])
  }

  /// Signal-free: a pedestal plus noise-scale jitter.
  static func flatCurve(_ pedestal: Float = 0.05, amplitude: Float = 0.003, count: Int = 10_000)
    -> FrameCurve
  {
    FrameCurve(planes: [(0..<count).map { pedestal + amplitude * Float($0 % 31) / 31 }])
  }

  /// The exact inverse affine of `reference`: an ideal fit recovers scale and offset.
  static func affine(_ reference: FrameCurve, scale: Double, offset: Double) -> FrameCurve {
    let quantiles = reference.quantiles.map { ($0 - offset) / scale }
    return FrameCurve(
      quantiles: quantiles, background: quantiles[3], noise: reference.noise / scale)
  }

  static let zwo = "ZWO ASI1600MM Pro"

  @Test("an exact affine is recovered; one corrupt probe moves it under 1%")
  func testExactAndRobust() {
    let reference = Self.skyCurve()
    let exact = CurveFit.fit(Self.affine(reference, scale: 1.8, offset: 0.02), onto: reference)
    #expect(abs(exact.scale - 1.8) <= 1e-9 && abs(exact.offset - 0.02) <= 1e-9)
    #expect(!exact.clamped && !exact.metaDisagree && !exact.metaSeeded && exact.residual < 1e-6)
    var corrupt = Self.affine(reference, scale: 1.8, offset: 0.02)
    corrupt.quantiles[11] *= 3
    #expect(abs(CurveFit.fit(corrupt, onto: reference).scale - 1.8) <= 1.8 * 0.01)
  }

  @Test("a measured scale is clamped at 10; a real 5.6× cross-gain ratio is not")
  func testClamp() {
    let reference = Self.skyCurve()
    let high = CurveFit.fit(Self.affine(reference, scale: 12, offset: 0), onto: reference)
    #expect(high.scale == 10 && high.clamped)
    let frameMeta = PhotomMeta(exposureMs: 30000, gain: 250, gainKnown: true, instrument: Self.zwo)
    let referenceMeta = PhotomMeta(
      exposureMs: 30000, gain: 400, gainKnown: true, instrument: Self.zwo)
    let gain = CurveFit.fit(
      Self.affine(reference, scale: 5.623, offset: 0.01), onto: reference, frameMeta: frameMeta,
      referenceMeta: referenceMeta)
    #expect(abs(gain.scale - 5.623) <= 5.623 * 0.01 && !gain.clamped && !gain.metaDisagree)
  }

  struct Seed: CustomTestStringConvertible, Sendable {
    let name: String
    let frame: (Float, Float)
    let reference: (Float, Float)
    let frameMeta: PhotomMeta
    let referenceMeta: PhotomMeta
    let scale: Double
    let tolerance: Double
    let seeded: Bool
    var testDescription: String { name }
  }

  static let seeds: [Seed] = [
    Seed(
      name: "flat narrowband seeds the g250→g400 prediction", frame: (0.05, 0.003),
      reference: (0.281, 0.003),
      frameMeta: PhotomMeta(exposureMs: 30000, gain: 250, gainKnown: true, instrument: zwo),
      referenceMeta: PhotomMeta(exposureMs: 30000, gain: 400, gainKnown: true, instrument: zwo),
      scale: 5.623, tolerance: 0.01, seeded: true),
    Seed(
      name: "a 20× exposure seed bypasses the clamp", frame: (0.05, 0.003), reference: (1.0, 0.003),
      frameMeta: PhotomMeta(exposureMs: 30000, gain: 200, gainKnown: true, instrument: zwo),
      referenceMeta: PhotomMeta(exposureMs: 600_000, gain: 200, gainKnown: true, instrument: zwo),
      scale: 20, tolerance: 1e-9, seeded: true),
    Seed(
      name: "sky-limited broadband is seeded, not the noise-width ratio", frame: (0.15, 0.005),
      reference: (0.05, 0.003),
      frameMeta: PhotomMeta(exposureMs: 90000, gain: 250, gainKnown: true, instrument: zwo),
      referenceMeta: PhotomMeta(exposureMs: 30000, gain: 250, gainKnown: true, instrument: zwo),
      scale: 1.0 / 3.0, tolerance: 1e-9, seeded: true),
    Seed(
      name: "flat curves without metadata are identity", frame: (0.05, 0.003),
      reference: (0.05, 0.003),
      frameMeta: PhotomMeta(), referenceMeta: PhotomMeta(), scale: 1, tolerance: 1e-9, seeded: false
    ),
    Seed(
      name: "differing gains on an unconfirmed law have no prediction", frame: (0.05, 0.003),
      reference: (0.05, 0.003),
      frameMeta: PhotomMeta(
        exposureMs: 30000, gain: 0, gainKnown: true, instrument: "Canon EOS Ra"),
      referenceMeta: PhotomMeta(
        exposureMs: 60000, gain: 120, gainKnown: true, instrument: "Canon EOS Ra"),
      scale: 1, tolerance: 1e-9, seeded: false),
    Seed(
      name: "an unknown gain has no prediction", frame: (0.05, 0.003), reference: (0.05, 0.003),
      frameMeta: PhotomMeta(exposureMs: 30000, instrument: zwo),
      referenceMeta: PhotomMeta(exposureMs: 600_000, instrument: zwo), scale: 1, tolerance: 1e-9,
      seeded: false),
    Seed(
      name: "ASICAP as creator confirms the gain law", frame: (0.45, 0.003),
      reference: (0.0203, 0.003),
      frameMeta: PhotomMeta(exposureMs: 15000, gain: 450, gainKnown: true, creator: "ASICAP  "),
      referenceMeta: PhotomMeta(exposureMs: 120_000, gain: 0, gainKnown: true, creator: "ASICap"),
      scale: 8 * pow(10, -450.0 / 200.0), tolerance: 1e-6, seeded: true),
    Seed(
      name: "instrument on one side, creator on the other", frame: (0.08, 0.003),
      reference: (0.03, 0.003),
      frameMeta: PhotomMeta(exposureMs: 90000, gain: 110, gainKnown: true, instrument: zwo),
      referenceMeta: PhotomMeta(exposureMs: 120_000, gain: 0, gainKnown: true, creator: "ASICAP"),
      scale: (120.0 / 90.0) * pow(10, -110.0 / 200.0), tolerance: 1e-6, seeded: true),
  ]

  @Test("flat curves: the header prediction leads, else nothing is invented", arguments: seeds)
  func testFlatSeeds(_ example: Seed) {
    let transform = CurveFit.fit(
      Self.flatCurve(example.frame.0, amplitude: example.frame.1),
      onto: Self.flatCurve(example.reference.0, amplitude: example.reference.1),
      frameMeta: example.frameMeta, referenceMeta: example.referenceMeta)
    #expect(abs(transform.scale - example.scale) <= example.tolerance)
    #expect(transform.metaSeeded == example.seeded && !transform.clamped)
  }

  @Test("the measurement wins over a disagreeing gain prediction; equal gains cancel")
  func testMetaDisagree() {
    let curve = Self.skyCurve()
    let zwoFit = CurveFit.fit(
      curve, onto: curve,
      frameMeta: PhotomMeta(exposureMs: 60000, gain: 0, gainKnown: true, instrument: Self.zwo),
      referenceMeta: PhotomMeta(exposureMs: 60000, gain: 120, gainKnown: true, instrument: Self.zwo)
    )
    #expect(abs(zwoFit.scale - 1) <= 1e-9 && zwoFit.metaDisagree && !zwoFit.metaSeeded)
    let canon = PhotomMeta(
      exposureMs: 60000, gain: 120, gainKnown: true, instrument: "Canon EOS Ra")
    let equal = CurveFit.fit(curve, onto: curve, frameMeta: canon, referenceMeta: canon)
    #expect(abs(equal.scale - 1) <= 1e-9 && !equal.metaDisagree)
  }

  @Test("a gross background disagreement is flagged, never applied; near-zero skies give identity")
  func testBackgroundRatio() {
    let seeded = CurveFit.fit(
      Self.flatCurve(0.288), onto: Self.flatCurve(0.014),
      frameMeta: PhotomMeta(exposureMs: 15000, gain: 450, gainKnown: true, instrument: Self.zwo),
      referenceMeta: PhotomMeta(
        exposureMs: 120_000, gain: 450, gainKnown: true, instrument: Self.zwo))
    #expect(seeded.method == .seeded && abs(seeded.scale - 8) <= 1e-9)
    #expect(seeded.backgroundDisagree && seeded.metaSeeded)
    let floor = CurveFit.fit(Self.flatCurve(0.0002), onto: Self.flatCurve(0.05))
    #expect(floor.method == .identity && abs(floor.scale - 1) <= 1e-9)
  }
}
