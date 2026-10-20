import Foundation
import StackKit
import TestSupport
import Testing

/// `CoverageGrid` and `CoverageCrop` are `coverage.go`: cases translated from `coverage_test.go`
/// (the mosaic union-canvas case aside: mosaic is not part of this port).
@Suite("Coverage — where the stacked frames land, and the common field")
struct CoverageCropTests {
  /// A rotation about the canvas centre: another night landing rotated on the anchor canvas.
  static func rotation(_ degrees: Double, _ w: Int, _ h: Int) -> [Double] {
    let radians = degrees * .pi / 180
    let (cosine, sine) = (cos(radians), sin(radians))
    let (cx, cy) = (Double(w) / 2, Double(h) / 2)
    return [
      cosine, -sine, cx - cosine * cx + sine * cy, sine, cosine, cy - sine * cx - cosine * cy, 0, 0,
      1,
    ]
  }

  static let identity = Homography.identity

  @Test("identity frames cover the canvas; the interior rectangle is ~the canvas")
  func testIdentityCoversCanvas() {
    let grid = CoverageGrid(
      homographies: [0: Self.identity, 1: Self.identity, 2: Self.identity],
      rejected: { _ in false },
      frameWidth: 640, frameHeight: 480)
    #expect(
      grid.frames == 3 && CoverageGrid.coveredFraction(grid.mask(minimumFraction: 0.3)) > 0.97)
    let rect = CoverageCrop.largestRectangle(
      grid.mask(minimumFraction: 0.3), width: grid.width, height: grid.height)
    #expect(Double(rect.area) / Double(grid.width * grid.height) > 0.97)
  }

  @Test("a 45° night leaves the corners uncovered at 3-of-4 depth; the centre carries all frames")
  func testRotatedNightLeavesWedges() {
    let grid = CoverageGrid(
      homographies: [
        0: Self.identity, 1: Self.identity, 2: Self.rotation(45, 640, 480),
        3: Self.rotation(45, 640, 480),
      ],
      rejected: { _ in false }, frameWidth: 640, frameHeight: 480)
    let mask = grid.mask(minimumFraction: 0.7)
    #expect(!mask[0] && mask[(grid.height / 2) * grid.width + grid.width / 2])
    let fraction = CoverageGrid.coveredFraction(mask)
    #expect(fraction > 0.2 && fraction < 0.9)
  }

  @Test("a graded-out frame contributes no coverage")
  func testRejectedFramesDoNotCount() {
    let grid = CoverageGrid(
      homographies: [0: Self.identity, 1: Self.rotation(90, 640, 480)], rejected: { $0 == 1 },
      frameWidth: 640, frameHeight: 480)
    #expect(grid.frames == 1 && grid.mask(minimumFraction: 0.3)[0])
  }

  @Test("the largest rectangle of a band is the band")
  func testLargestRectangle() {
    let mask = (0..<32).map { (2...5).contains($0 % 8) }
    #expect(
      CoverageCrop.largestRectangle(mask, width: 8, height: 4)
        == EdgeRect(x0: 2, y0: 0, x1: 6, y1: 4))
  }

  @Test("a night's footprint counts only its own frames; a rotated night is its rotated rectangle")
  func testFootprint() {
    let homographies = [0: Self.rotation(45, 640, 480), 1: Self.identity, 2: Self.identity]
    let rotated = CoverageGrid.footprint(
      0..<1, homographies: homographies, rejected: { _ in false }, frameWidth: 640, frameHeight: 480
    )
    let anchor = CoverageGrid.footprint(
      1..<3, homographies: homographies, rejected: { _ in false }, frameWidth: 640, frameHeight: 480
    )
    #expect(!rotated[0] && anchor[0] && rotated[30 * 80 + 40])
    #expect(CoverageGrid.coveredFraction(anchor) > CoverageGrid.coveredFraction(rotated))
  }

  @Test(
    "channels are cut to the common field; a sliver keeps the full field, with the reason",
    .scratchDirectory)
  func testApply() throws {
    let out = try ScratchDirectory.url
    for filter in ["R", "G"] {
      try FloatFITS.write(
        out.appendingPathComponent("aligned_\(filter).fits"), width: 640, height: 480,
        planes: [[Float](repeating: 0.1, count: 640 * 480)])
    }
    let full = CoverageGrid(
      homographies: [0: Self.identity], rejected: { _ in false }, frameWidth: 640, frameHeight: 480)
    let rotated = CoverageGrid(
      homographies: [0: Self.rotation(30, 640, 480)], rejected: { _ in false }, frameWidth: 640,
      frameHeight: 480)
    var journal = PreprocessJournal()
    let (channels, record) = CoverageCrop.apply(
      ["R": "aligned_R", "G": "aligned_G"], grids: ["R": full, "G": rotated], minimumFraction: 0.3,
      out: out,
      journal: &journal)
    #expect(channels == ["R": "combine_R", "G": "combine_G"] && record?.applied == true)
    #expect(record.map { $0.fraction > 0.35 && $0.fraction < 0.98 } == true)

    let far = CoverageGrid(
      homographies: [0: [1, 0, 600, 0, 1, 0, 0, 0, 1]], rejected: { _ in false }, frameWidth: 640,
      frameHeight: 480)
    var second = PreprocessJournal()
    let (kept, sliver) = CoverageCrop.apply(
      ["R": "aligned_R", "G": "aligned_G"], grids: ["R": full, "G": far], minimumFraction: 0.3,
      out: out,
      journal: &second)
    #expect(kept == ["R": "aligned_R", "G": "aligned_G"] && sliver?.applied == false)
    #expect(
      second.warnings.first?.hasPrefix("coverage crop skipped: common coverage rectangle is only")
        == true)
  }
}
