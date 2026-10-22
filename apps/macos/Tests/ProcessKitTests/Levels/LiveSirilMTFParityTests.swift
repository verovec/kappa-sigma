import Foundation
import ImageKit
import Metal
import ProcessKit
import StackKit
import TestSupport
import Testing

/// The histogram transformation against Siril's own `mtf low mid high` on a 256×256 piece of
/// run #78's `rgb_base` (the 0067 finishing crop, hash-checked first).
@Suite(
  "Live levels — histogram transformation against Siril mtf on run #78", .finishOracle,
  .tags(.live), .enabled(if: (try? SirilTool.locate()) != nil, "siril-cli absent"),
  .enabled(if: MTLCreateSystemDefaultDevice() != nil), .serialized, .timeLimit(.minutes(2)))
struct LiveSirilMTFParityTests {
  @Test("mean |Δ| ≤ 1/65535 against Siril mtf 0.002 0.02 0.95", .scratchDirectory)
  func testLevelsVsSirilMtf() async throws {
    let root = try #require(FinishOracle.root)
    let manifest = try FinishOracle.manifest()
    let layer = try #require(manifest.layers.first { $0.path == "crop/rgb_base.fits" })
    try #require(FinishOracle.verify([layer], root: root) == [])
    let scratch = try ScratchDirectory.url
    let crop = scratch.appendingPathComponent("crop.fits")
    try FITSFile.read(at: root.appendingPathComponent(layer.path))
      .writeCrop(to: crop, x0: 384, y0: 256, x1: 640, y1: 512)
    let (low, mid, high) = (0.002, 0.02, 0.95)

    _ = try await SirilRunner.live(binary: try SirilTool.locate()).run(
      SirilScript([.load("crop"), .mtf(low: low, mid: mid, high: high), .save("siril")]),
      scratch, { _ in })
    let siril = try FITSFile.read(at: scratch.appendingPathComponent("siril.fits")).image()

    let image = try FITSFile.read(at: crop).image()
    let device = try #require(MTLCreateSystemDefaultDevice())
    var params = ParamSet(schema: LevelsProcess.schema)
    try params.set("rgbShadows", .number(low))
    try params.set("rgbMidtones", .number(mid))
    try params.set("rgbHighlights", .number(high))
    let input = try GPUImage(
      device: device, width: image.width, height: image.height, planes: image.planes)
    let ours = try ProcessRunner(device: device).run(
      try LevelsProcess(params: params, device: device), input: input,
      stats: LayerStats(channels: [])
    ).read()

    #expect(ours.count == siril.planes.count)
    let differences = zip(ours, siril.planes).flatMap { zip($0, $1).map { Double(abs($0 - $1)) } }
    let mean = differences.reduce(0, +) / Double(differences.count)
    #expect(
      mean <= 1.0 / 65535,
      "mean |Δ| \(mean * 65535)/65535, max \((differences.max() ?? 0) * 65535)/65535")
  }
}
