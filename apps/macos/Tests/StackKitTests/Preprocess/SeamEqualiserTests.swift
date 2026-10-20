import Foundation
import StackKit
import TestSupport
import Testing

/// `SeamNoiseWeights` and `SeamNoiseEqualiser` are `seamnoise.go`: cases translated from
/// `seamnoise_test.go`, plus the in-place pass on a master.
@Suite("Seam noise — the depth step faded on the master")
struct SeamEqualiserTests {
  /// Left half `shallow` frames deep, right half `deep`.
  static func twoZones(_ size: Int, shallow: UInt16, deep: UInt16) -> CoverageGrid {
    var grid = CoverageGrid(canvasWidth: size, canvasHeight: size)
    grid.counts = (0..<grid.counts.count).map { $0 % grid.width >= grid.width / 2 ? deep : shallow }
    grid.frames = Int(deep)
    return grid
  }

  @Test("uniform depth is no step; a mismatched grid is refused")
  func testSkips() {
    let uniform = SeamNoiseWeights.weights(Self.twoZones(512, shallow: 5, deep: 5), width: 512, height: 512)
    #expect(uniform.weights == nil && uniform.reason.contains("nearly uniform"))
    let mismatch = SeamNoiseWeights.weights(Self.twoZones(512, shallow: 1, deep: 5), width: 1024, height: 1024)
    #expect(mismatch.weights == nil && mismatch.reason.contains("does not match"))
  }

  @Test("the weight ramps smoothly from the shallow zone to ~0 in the full-depth core, capped at 2.5")
  func testTwoZoneRamp() throws {
    let size = 512
    let weights = try #require(SeamNoiseWeights.weights(Self.twoZones(size, shallow: 1, deep: 5), width: size, height: size).weights)
    let middle = (size / 2) * size
    #expect(abs(weights[middle + size - 16]) <= 0.05)
    #expect(weights[middle + 16] > 0.5 && weights[middle + 16] <= 2.5)
    let jumps = ((size / 2 - 96)..<(size / 2 + 96)).map { abs(weights[middle + $0] - weights[middle + $0 + 1]) }
    #expect((jumps.max() ?? 0) < 0.08)
  }

  @Test("never-covered pixels stay exactly 0; a narrow shallow band keeps a real weight")
  func testNeverCovered() throws {
    let size = 512
    var grid = Self.twoZones(size, shallow: 1, deep: 5)
    for index in grid.counts.indices where index % grid.width < grid.width / 3 { grid.counts[index] = 0 }
    let weights = try #require(SeamNoiseWeights.weights(grid, width: size, height: size).weights)
    let middle = (size / 2) * size
    #expect((0..<((grid.width / 3) * 8 - 8)).allSatisfy { weights[middle + $0] == 0 })
    #expect(weights[middle + (grid.width / 3 + grid.width / 2) / 2 * 8] > 0.2)
  }

  @Test("a colour master is luminance-only, a mono one keeps the plane pass")
  func testMode() {
    #expect(SeamNoiseEqualiser.mode(planes: 3) == "luminance" && SeamNoiseEqualiser.mode(planes: 1) == "mono")
  }

  @Test("the pass rewrites the master in place, lowers its noise, and records the depths", .scratchDirectory)
  func testEqualise() throws {
    let size = 256
    var gaussian = SeededGaussian(seed: 9)
    let url = try FloatFITS.write(
      try ScratchDirectory.url.appendingPathComponent("master_L.fits"), width: size, height: size,
      planes: [(0..<size * size).map { _ in Float(0.1 + 0.01 * gaussian.next()) }])
    let record = SeamNoiseEqualiser.equalise(url, grid: Self.twoZones(size, shallow: 1, deep: 5))
    #expect(record.applied && record.mode == "mono" && record.depthMin == 1 && record.depthMax == 5)
    #expect(record.weightMax > 0.5 && record.sigmaAfter < record.sigmaBefore)
    let uniform = SeamNoiseEqualiser.equalise(url, grid: Self.twoZones(size, shallow: 3, deep: 3))
    #expect(!uniform.applied && uniform.reason == "stack depth nearly uniform (3→3) — no visible noise step")
  }
}
