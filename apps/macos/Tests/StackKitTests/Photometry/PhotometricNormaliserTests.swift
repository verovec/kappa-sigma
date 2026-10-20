import Foundation
import StackKit
import TestSupport
import Testing

/// `PhotometricNormaliser` is `photom.NormalizeGroups`: cases translated from
/// `internal/photom/normalize_test.go` and `masked_test.go`. The Go fixtures draw Gaussian noise
/// from `math/rand`; these use a seeded generator of their own, so they assert the same
/// properties with the same tolerances, not the same samples.
@Suite("PhotometricNormaliser — nights mapped onto the reference night", .serialized)
struct PhotometricNormaliserTests {
  static let size = 64

  /// 85% sky (pedestal + noise), 15% signal ramp.
  static func skyPlane(seed: UInt64) -> [Float] {
    var gaussian = SeededGaussian(seed: seed)
    let count = size * size
    return (0..<count).map { index in
      index % 100 < 85
        ? Float(0.2 + 0.01 * gaussian.next()) : 0.2 + 0.5 * Float(index) / Float(count)
    }
  }

  /// Signal-free: a pedestal with 2% noise.
  static func flatPlane(_ level: Float, seed: UInt64) -> [Float] {
    var gaussian = SeededGaussian(seed: seed)
    return (0..<size * size).map { _ in level + level * 0.02 * Float(gaussian.next()) }
  }

  static func write(_ name: String, _ plane: [Float], copies: Int) throws -> [String] {
    try (0..<copies).map { index in
      try FloatFITS.write(
        ScratchDirectory.url.appendingPathComponent("\(name)\(index).fits"), width: size,
        height: size,
        planes: [plane]
      ).path
    }
  }

  @Test(
    "a dim, offset night is scaled onto the reference; its median lands within 1%",
    .scratchDirectory)
  func testScalesGroupToReference() throws {
    let reference = Self.skyPlane(seed: 12345)
    let pathsA = try Self.write("a", reference, copies: 3)
    let pathsB = try Self.write("b", reference.map { 0.5 * $0 + 0.01 }, copies: 3)
    let (records, notes) = PhotometricNormaliser.normalise([
      PhotomGroup(paths: pathsA, label: "A", isReference: true),
      PhotomGroup(paths: pathsB, label: "B"),
    ])
    #expect(records.map(\.label) == ["A", "B"] && !records[0].applied && records[1].applied)
    #expect(abs(records[1].scale - 2) <= 0.05 && notes.isEmpty)
    let (aCurve, bCurve) = (
      try PhotometricNormaliser.measure(pathsA[0]), try PhotometricNormaliser.measure(pathsB[0])
    )
    #expect(abs(aCurve.quantiles[5] - bCurve.quantiles[5]) <= abs(aCurve.quantiles[5]) * 0.01)
  }

  @Test(
    "an identical night is left byte for byte; a 16-bit night cannot be rewritten",
    .scratchDirectory)
  func testSkips() throws {
    let plane = Self.skyPlane(seed: 999)
    let pathsA = try Self.write("ha", plane, copies: 2)
    let pathsB = try Self.write("hb", plane, copies: 2)
    let before = try Data(contentsOf: URL(fileURLWithPath: pathsB[0]))
    let (same, _) = PhotometricNormaliser.normalise([
      PhotomGroup(paths: pathsA, label: "A", isReference: true),
      PhotomGroup(paths: pathsB, label: "B"),
    ])
    let after = try Data(contentsOf: URL(fileURLWithPath: pathsB[0]))
    #expect(!same[1].applied && after == before)

    let sixteen = try TestFITS.write(
      "c16.fits", in: try ScratchDirectory.url, width: Self.size, height: Self.size,
      planes: [(0..<Self.size * Self.size).map { UInt16(1000 + $0 % 5000) }], cards: [:])
    let raw = try Data(contentsOf: sixteen)
    let (records, notes) = PhotometricNormaliser.normalise([
      PhotomGroup(paths: [pathsA[0]], label: "A", isReference: true),
      PhotomGroup(paths: [sixteen.path], label: "C16"),
    ])
    let untouched = try Data(contentsOf: sixteen)
    #expect(!records[1].applied && untouched == raw)
    #expect(notes.contains { $0.contains("not 32-bit float") })
  }

  @Test(
    "flat narrowband nights take the gain prediction; the sky lands within 2%", .scratchDirectory)
  func testMetaSeededNarrowband() throws {
    let trueScale = 5.623
    let reference = Self.flatPlane(0.2, seed: 11)
    let pathsA = try Self.write("na", reference, copies: 2)
    let pathsB = try Self.write("nb", reference.map { $0 / Float(trueScale) }, copies: 2)
    let zwo = "ZWO ASI1600MM Pro"
    let (records, notes) = PhotometricNormaliser.normalise([
      PhotomGroup(
        paths: pathsA, label: "Ha g400",
        meta: PhotomMeta(exposureMs: 30000, gain: 400, gainKnown: true, instrument: zwo),
        isReference: true, session: "2023-02-28"),
      PhotomGroup(
        paths: pathsB, label: "Ha g250",
        meta: PhotomMeta(exposureMs: 30000, gain: 250, gainKnown: true, instrument: zwo),
        sessionID: 42, session: "2023-03-15"),
    ])
    #expect(records[0].isReference && records[0].session == "2023-02-28")
    #expect(records[1].metaSeeded && records[1].applied && !records[1].clamped)
    #expect(abs(records[1].scale - trueScale) <= trueScale * 0.02)
    #expect(records[1].sessionID == 42 && records[1].session == "2023-03-15")
    #expect(notes.contains { $0.contains("seeded from header exposure/gain") })
    let (aCurve, bCurve) = (
      try PhotometricNormaliser.measure(pathsA[0]), try PhotometricNormaliser.measure(pathsB[0])
    )
    #expect(abs(aCurve.background - bCurve.background) <= abs(aCurve.background) * 0.02)
  }

  @Test(
    "the no-clip gate runs inside the normaliser: offset-only, noise not amplified",
    .scratchDirectory)
  func testNoClipGateWiring() throws {
    var gaussian = SeededGaussian(seed: 3)
    let zeroSky = (0..<Self.size * Self.size).map { _ in Float(0.0001 + 0.001 * gaussian.next()) }
    let reference = try Self.write("ref", zeroSky, copies: 2)
    let bright = try Self.write("g", Self.flatPlane(0.5, seed: 7), copies: 2)
    let zwo = "ZWO ASI1600MM Pro"
    let (records, notes) = PhotometricNormaliser.normalise([
      PhotomGroup(
        paths: reference, label: "deep",
        meta: PhotomMeta(exposureMs: 120_000, gain: 450, gainKnown: true, instrument: zwo),
        isReference: true),
      PhotomGroup(
        paths: bright, label: "shallow-bright",
        meta: PhotomMeta(exposureMs: 15000, gain: 450, gainKnown: true, instrument: zwo)),
    ])
    #expect(
      records[1].reverted && records[1].method == .offsetOnly && abs(records[1].scale - 1) <= 1e-9)
    #expect(notes.contains { $0.contains("would clip its sky below zero") })
    #expect(try PhotometricNormaliser.measure(bright[0]).noise < 0.02)
  }

  @Test("without a flag the largest night is the reference; unreadable, nothing is rewritten")
  func testReferenceFallbacks() {
    let big = (1...10).map { "/nonexistent/big_\($0).fits" }
    let (records, notes) = PhotometricNormaliser.normalise([
      PhotomGroup(
        paths: ["/nonexistent/small_1.fits", "/nonexistent/small_2.fits"], label: "small"),
      PhotomGroup(paths: big, label: "big"),
    ])
    #expect(records.map(\.label) == ["small", "big"] && records.allSatisfy { !$0.applied })
    // Seven evenly spaced probes of the ten, each a note, then the skip.
    let probes = big.prefix(7).map { "photometric reference \"big\": unreadable frame \($0)" }
    #expect(
      notes == probes + [
        "photometric reference \"big\": no readable frames — normalization skipped"
      ])
  }
}
