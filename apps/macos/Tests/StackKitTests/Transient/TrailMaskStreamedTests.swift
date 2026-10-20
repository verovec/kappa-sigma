import Foundation
import StackKit
import TestSupport
import Testing

/// `TrailMask.maskStreamed` ports `transient.MaskCrossFrameStreamed`, and `TrailMaskBudget` the
/// memory gate (`budget.go`, `trailBasisPlan`): cases of `streamed_test.go` and
/// `trailmask_budget_test.go`.
@Suite("TrailMask streamed — one frame at a time against a bounded basis", .serialized)
struct TrailMaskStreamedTests {
  typealias F = TrailMaskFrames

  static func files(_ count: Int, amplitude: (Int) -> Float) throws -> [URL] {
    try F.write(
      (0..<count).map { F.frame($0, amplitude: amplitude($0)) }, in: ScratchDirectory.url)
  }

  @Test("a basis covering every frame reproduces the in-memory pass bit for bit", .scratchDirectory)
  func testFullBasisMatchesInMemory() async throws {
    let amplitude: (Int) -> Float = { $0 == 0 ? 0.6 : 0 }
    var frames = (0..<8).map { [F.frame($0, amplitude: amplitude($0))] }
    let inMemory = try await TrailMask.mask(&frames, width: F.side, height: F.side, k: 3)
    let urls = try Self.files(8, amplitude: amplitude)
    let streamed = try await TrailMask.maskStreamed(urls, k: 3, basis: 100)
    #expect(streamed.summary == inMemory.summary)
    #expect(try F.read(urls[0]) == frames[0][0])
  }

  @Test("a five-frame basis over ten still paints a streak in a frame outside it", .scratchDirectory)
  func testSmallBasisCleansTrail() async throws {
    let urls = try Self.files(10) { $0 == 3 ? 0.6 : 0 }
    let summary = try await TrailMask.maskStreamed(urls, k: 3, basis: 5).summary
    #expect(summary.segments >= 1 && summary.rejected == 0)
    let plane = try F.read(urls[3])
    #expect(F.maxAlongDiagonal(plane) < 0.2 && abs(F.starPixel(plane) - F.starValue) <= 0.05)
  }

  @Test("the fixed-pattern test holds against an 8-of-10 basis", .scratchDirectory)
  func testSubsetBasisRejectsFixedPattern() async throws {
    let urls = try Self.files(10) { $0 < 4 ? 0.6 : 0 }
    let summary = try await TrailMask.maskStreamed(urls, k: 3, basis: 8).summary
    #expect(summary.rejected > 0 && summary.segments == 0)
  }

  @Test("the recurring pass repairs a frame left out of the basis", .scratchDirectory)
  func testRecurringOnSubsetBasis() async throws {
    var frames = (0..<10).map { F.frame($0) }
    for index in frames.indices {
      let start = 20 + 27 * Double(index)
      F.addStreak(&frames[index], amplitude: 0.6, along: start...(start + 30))
    }
    let urls = try F.write(frames, in: ScratchDirectory.url)
    let summary = try await TrailMask.maskStreamed(urls, k: 3, basis: 8).summary
    #expect(summary.recurring >= 1)
    let plane = try F.read(urls[4])
    let middle = 20 + 27 * 4 + 15
    #expect(plane[middle * F.side + middle] < 0.2)
    #expect(abs(F.starPixel(plane) - F.starValue) <= 0.05)
  }

  @Test(
    "evenly spaced basis indices",
    arguments: [(3, 5, [0, 1, 2]), (10, 5, [0, 2, 4, 6, 8]), (10, 8, [0, 1, 2, 3, 5, 6, 7, 8])])
  func testEvenIndices(count: Int, basis: Int, expected: [Int]) {
    #expect(TrailMaskBudget.evenIndices(count, basis) == expected)
    #expect(TrailMaskBudget.evenIndices(129, 33).count == 33)
  }

  static let gib = Int64(1) << 30
  static let monoFrame = Int64(6248) * 4176 * 4

  @Test(
    "the in-memory pass while 3·n·frame fits, else a basis in [16, 48] and ≤ n",
    arguments: [
      (20, monoFrame, 40 * gib, false, 0),
      (99, monoFrame * 3, 15 * gib, true, 19),
      (99, monoFrame, 15 * gib, true, 48),
      (99, monoFrame * 3, 2 * gib, true, 16),
      (12, monoFrame * 3, 1 * gib, true, 12),
      (99, 0, 1 * gib, false, 0),
    ])
  func testBasisPlan(frames: Int, frameBytes: Int64, budget: Int64, streamed: Bool, basis: Int) {
    let plan = TrailMaskBudget.plan(frames: frames, frameBytes: frameBytes, budget: budget)
    #expect(plan.streamed == streamed && plan.basis == basis)
  }

  @Test(
    "the budget: the environment override in GiB, else half the physical memory",
    arguments: [
      (["ASTRO_TRAIL_MASK_MEM_GB": "2"], Int64(2) << 30),
      (["ASTRO_TRAIL_MASK_MEM_GB": "0"], Int64(24) << 30),
      ([:], Int64(24) << 30),
    ])
  func testBudget(environment: [String: String], expected: Int64) {
    #expect(
      TrailMaskBudget.bytes(environment: environment, physicalMemory: UInt64(48) << 30)
        == expected)
  }
}
