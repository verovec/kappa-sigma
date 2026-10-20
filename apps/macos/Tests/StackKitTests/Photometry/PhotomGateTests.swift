import StackKit
import Testing

/// The pre-apply no-clip gate (`TestDegradeClippingTransform`) and the masked measurement
/// (`masked_test.go`), translated with their literal values.
@Suite("Photometry — the no-clip gate and masked curves")
struct PhotomGateTests {
  struct Case: CustomTestStringConvertible, Sendable {
    let name: String
    let transform: PhotomTransform
    let group: FrameCurve
    let reference: FrameCurve
    let method: PhotomTransform.Method
    let reverted: Bool
    var testDescription: String { name }
  }

  static let group = FrameCurve(background: 0.30, noise: 0.004)
  static let reference = FrameCurve(background: 0.02, noise: 0.002)

  static let cases: [Case] = [
    Case(
      name: "healthy shrink passes untouched",
      transform: PhotomTransform(scale: 0.05, offset: 0.005, method: .seeded), group: group,
      reference: reference, method: .seeded, reverted: false),
    Case(
      name: "legit noise blow-up without clipping passes (no upper bound)",
      transform: PhotomTransform(scale: 6, offset: 0.01, method: .seeded),
      group: FrameCurve(background: 0.05, noise: 0.001),
      reference: FrameCurve(background: 0.31, noise: 0.02),
      method: .seeded, reverted: false),
    Case(
      name: "clipping transform degrades to the measured bg ratio",
      transform: PhotomTransform(scale: 8, offset: 0.02 - 8 * 0.30, method: .seeded), group: group,
      reference: reference, method: .bgMatched, reverted: true),
    Case(
      name: "clipping transform with no usable backgrounds degrades to offset-only",
      transform: PhotomTransform(scale: 8, offset: 0.001 - 8 * 0.30, method: .seeded), group: group,
      reference: FrameCurve(background: 0.001, noise: 0.002), method: .offsetOnly, reverted: true),
    Case(
      name: "a sky that already straddles zero is not blamed on the transform",
      transform: PhotomTransform(scale: 1.02, offset: -0.001, method: .measured),
      group: FrameCurve(background: 0.001, noise: 0.002),
      reference: FrameCurve(background: 0.0011, noise: 0.002),
      method: .measured, reverted: false),
  ]

  @Test("a transform that floors the sky is degraded, and says so", arguments: cases)
  func testDegradeClippingTransform(_ example: Case) {
    let degraded = PhotometricNormaliser.degradeClipping(
      "g", example.transform, group: example.group, reference: example.reference)
    #expect((degraded != nil) == example.reverted)
    guard let (transform, note) = degraded else { return }
    #expect(transform.method == example.method && note.contains("would clip its sky below zero"))
    #expect(
      !(transform.method == .bgMatched && PhotometricNormaliser.clipsSky(transform, example.group)))
  }

  /// Left half at `low`, right half at `high`.
  static func halves(_ size: Int, _ low: Float, _ high: Float) -> [[Float]] {
    [(0..<size * size).map { $0 % size >= size / 2 ? high : low }]
  }

  @Test(
    "a full mask matches the unmasked curve; a half mask never sees the other half; too few is nil")
  func testMasked() throws {
    let planes = Self.halves(512, 0.05, 0.30)
    let masked = try #require(
      FrameCurve.masked(planes: planes, width: 512, height: 512) { _, _ in true })
    let full = FrameCurve(planes: planes)
    #expect(
      abs(full.background - masked.background) <= 1e-3
        && abs(full.quantiles[11] - masked.quantiles[11]) <= 1e-3)
    let left = try #require(
      FrameCurve.masked(planes: Self.halves(512, 0.05, 0.90), width: 512, height: 512) { x, _ in
        x < 256
      })
    #expect(
      abs(left.background - 0.05) <= 1e-4 && abs(left.quantiles[11] - 0.05) <= 1e-4
        && left.saturatedFraction == 0)
    #expect(
      FrameCurve.masked(planes: Self.halves(64, 0.05, 0.30), width: 64, height: 64) { _, _ in true }
        == nil)
  }
}
