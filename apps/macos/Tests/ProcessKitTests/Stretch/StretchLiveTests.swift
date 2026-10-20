import Foundation
import ImageKit
import Metal
import ProcessKit
import StackKit
import TestSupport
import Testing

/// The MTF stretch against Siril's own `autostretch -2.8 0.25` on a 256×256 piece of run #78's
/// `rgb_base` (the 0067 finishing crop, hash-checked first).
@Suite(
  "Live stretch — MTF against Siril autostretch on run #78", .finishOracle, .tags(.live),
  .enabled(if: (try? SirilTool.locate()) != nil, "siril-cli absent"),
  .enabled(if: MTLCreateSystemDefaultDevice() != nil), .serialized, .timeLimit(.minutes(2)))
struct StretchLiveTests {
  /// The bundle statistics of a plane: exact median and 1.4826 · MAD over every pixel.
  static func stats(_ plane: [Float]) -> ChannelStats {
    let sorted = plane.map(Double.init).sorted()
    let median = sorted[sorted.count / 2]
    let deviations = sorted.map { abs($0 - median) }.sorted()
    return ChannelStats(
      median: median, madn: 1.4826 * deviations[deviations.count / 2],
      minimum: sorted.first ?? 0, maximum: sorted.last ?? 1)
  }

  @Test("mean |Δ| ≤ 1/255 against Siril autostretch -2.8 0.25 (unlinked)", .scratchDirectory)
  func testMTFMatchesSirilAutostretch() async throws {
    let root = try #require(FinishOracle.root)
    let manifest = try FinishOracle.manifest()
    let layer = try #require(manifest.layers.first { $0.path == "crop/rgb_base.fits" })
    #expect(FinishOracle.verify([layer], root: root) == [], "the crop is the recorded one")
    let scratch = try ScratchDirectory.url
    let crop = scratch.appendingPathComponent("crop.fits")
    try FITSFile.read(at: root.appendingPathComponent(layer.path))
      .writeCrop(to: crop, x0: 384, y0: 256, x1: 640, y1: 512)

    _ = try await SirilRunner.live(binary: try SirilTool.locate()).run(
      SirilScript([.load("crop"), .autostretch(linked: false, target: 0.25), .save("siril")]),
      scratch, { _ in })
    let siril = try FITSFile.read(at: scratch.appendingPathComponent("siril.fits")).image()

    let image = try FITSFile.read(at: crop).image()
    let device = try #require(MTLCreateSystemDefaultDevice())
    var params = ParamSet(schema: StretchProcess.schema)
    try params.set("linked", .flag(false))
    let input = try GPUImage(
      device: device, width: image.width, height: image.height, planes: image.planes)
    let ours = try ProcessRunner(device: device).run(
      try StretchProcess(params: params, device: device), input: input,
      stats: LayerStats(channels: image.planes.map(Self.stats))
    ).read()

    #expect(ours.count == siril.planes.count)
    let differences = zip(ours, siril.planes).flatMap { zip($0, $1).map { Double(abs($0 - $1)) } }
    let mean = differences.reduce(0, +) / Double(differences.count)
    #expect(mean <= 1.0 / 255, "mean |Δ| \(mean * 255)/255, max \((differences.max() ?? 0) * 255)/255")
  }
}
