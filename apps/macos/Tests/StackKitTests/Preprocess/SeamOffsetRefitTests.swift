import Foundation
import StackKit
import TestSupport
import Testing

/// `SeamOffsetRefit` is `seamoffset.go`: cases translated from `seamoffset_test.go` with their
/// literal values.
@Suite("SeamOffsetRefit — each night's pedestal on the anchor's, inside their overlap")
struct SeamOffsetRefitTests {
  static func flat(_ background: Double, _ noise: Double) -> FrameCurve {
    FrameCurve(q: Array(repeating: background, count: 14), background: background, noise: noise)
  }

  @Test(
    "the guarded pedestal",
    arguments: [
      (0.13, 0.010, -0.03, ""), (0.08, 0.010, 0.02, ""), (0.1001, 0.010, 0, "below stack visibility"),
      (0.30, 0.010, 0, "sanity cap"), (0.145, 0.060, 0, "clip"),
    ])
  func testDelta(background: Double, noise: Double, delta: Double, reason: String) {
    let result = SeamOffsetRefit.delta(group: Self.flat(background, noise), anchor: Self.flat(0.10, 0.010))
    if reason.isEmpty {
      #expect(result.reason.isEmpty && abs(result.delta - delta) <= 1e-9)
    } else {
      #expect(result.delta == 0 && result.reason.contains(reason))
    }
  }

  @Test("an overlap filled with extended signal is not a pedestal")
  func testContaminated() {
    var group = Self.flat(0.14, 0.010)
    group.q[2] = 0.10
    let result = SeamOffsetRefit.delta(group: group, anchor: Self.flat(0.10, 0.010))
    #expect(result.delta == 0 && result.reason.contains("contaminated"))
  }

  static func nights() -> [FrameSet] {
    ["2020-05-06", "2020-04-26"].map {
      FrameSet(key: SetKey(type: .light, filter: "L", session: $0), frames: [], indices: [])
    }
  }

  static func write(_ folder: URL, from start: Int, count: Int, level: Float) throws {
    for index in start..<(start + count) {
      try FloatFITS.write(
        folder.appendingPathComponent(String(format: "light_%05d.fits", index + 1)), width: 256, height: 256,
        planes: [[Float](repeating: level, count: 256 * 256)])
    }
  }

  static let identities = Dictionary(uniqueKeysWithValues: (0..<4).map { ($0, Homography.identity) })

  @Test("a planted +0.03 pedestal is refitted onto the anchor sky; the anchor is untouched", .scratchDirectory)
  func testAppliesPlantedDelta() throws {
    let folder = try ScratchDirectory.url
    try Self.write(folder, from: 0, count: 2, level: 0.10)
    try Self.write(folder, from: 2, count: 2, level: 0.13)
    let records = try SeamOffsetRefit.refit(
      Self.nights(), spans: [0..<2, 2..<4], anchor: 0,
      review: RegistrationReview(frameHomographies: Self.identities, nights: 2), width: 256, height: 256
    ) { folder.appendingPathComponent(String(format: "light_%05d.fits", $0 + 1)) }
    let record = try #require(records.first)
    #expect(records.count == 1 && record.applied && abs(record.delta + 0.03) <= 2e-3, "\(record.reason)")
    #expect(record.session == "2020-04-26")
    let anchor = try PhotometricNormaliser.measure(folder.appendingPathComponent("light_00001.fits").path)
    let night = try PhotometricNormaliser.measure(folder.appendingPathComponent("light_00003.fits").path)
    #expect(abs(anchor.background - 0.10) <= 1e-6 && abs(night.background - 0.10) <= 2e-3)
  }

  @Test("a night whose frames cannot be read is left alone, with a reason", .scratchDirectory)
  func testSoftFails() throws {
    let folder = try ScratchDirectory.url
    try Self.write(folder, from: 0, count: 2, level: 0.10)
    let records = try SeamOffsetRefit.refit(
      Self.nights(), spans: [0..<2, 2..<4], anchor: 0,
      review: RegistrationReview(frameHomographies: Self.identities, nights: 2), width: 256, height: 256
    ) { folder.appendingPathComponent(String(format: "light_%05d.fits", $0 + 1)) }
    #expect(records.count == 1 && !records[0].applied && !records[0].reason.isEmpty)
  }
}
