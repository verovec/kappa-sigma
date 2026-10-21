import Foundation
import ImageKit
import Metal
import ProcessKit
import TestSupport
import Testing

/// HDR against hdrcomp's own output on run #78's core: `crop/hdr_only.fits` of the 0067 finishing
/// oracle, recorded by the PO's tool on `crop/rgb_base.fits` (both hash-checked first).
@Suite(
  "Live HDR — core compression against hdrcomp on run #78", .finishOracle, .tags(.live),
  .enabled(if: MTLCreateSystemDefaultDevice() != nil), .serialized, .timeLimit(.minutes(2)))
struct HDRLiveTests {
  /// The value after `flag` in a recorded command line.
  static func flag(_ flag: String, in flags: [String]) throws -> Double {
    let index = try #require(flags.firstIndex(of: flag), "\(flag) not recorded")
    return try #require(Double(flags[index + 1]))
  }

  @Test("mean |Δ| ≤ 1e-9 and max |Δ| ≤ 1e-6 (linear) against hdrcomp's recorded hdr_only")
  func testParityHdrcomp() throws {
    let root = try #require(FinishOracle.root)
    let manifest = try FinishOracle.manifest()
    let stage = try #require(manifest.stages.first { $0.name == "hdr_only" })
    let base = try #require(manifest.layers.first { $0.path == "crop/rgb_base.fits" })
    let recorded = try #require(stage.outputs.first { $0.variant == "crop" })
    try #require(FinishOracle.verify([base, recorded], root: root) == [])
    let image = try FITSFile.read(at: root.appendingPathComponent(base.path)).image()
    let expected = try FITSFile.read(at: root.appendingPathComponent(recorded.path)).image()

    // hdrcomp took t1 and s as multiples of a sky it measured itself; the process takes them
    // absolute above the bundle sky. The same absolute values on the wire = the same render.
    let legacySky = HDROracle.legacySky(HDROracle.luminance(image.planes))
    let stats = LayerStats(channels: image.planes.map(StretchLiveTests.stats))
    let bundleSky = stats.channels.map(\.median).reduce(0, +) / Double(stats.channels.count)
    var params = ParamSet(schema: HDRProcess.schema)
    try params.set("enabled", .flag(true))
    let knee = try Self.flag("-t1", in: stage.flags) * legacySky - bundleSky
    // `set` would clamp a knee outside the schema bounds and the parity would fail for no shown
    // reason: refuse it here instead.
    try #require((0...0.1).contains(knee), "hdrcomp's t1 lies \(knee) from the bundle sky")
    try params.set("kneeAboveSky", .number(knee))
    try params.set("softness", .number(try Self.flag("-s", in: stage.flags) * legacySky))
    try params.set("sigma", .number(try Self.flag("-sigma", in: stage.flags)))
    // hdrcomp's default opening radius: the recorded flags leave it unset.
    try params.set("openRadius", .number(16))

    let device = try #require(MTLCreateSystemDefaultDevice())
    let input = try GPUImage(device: device, image: image)
    let ours = try ProcessRunner(device: device).run(
      try HDRProcess(params: params, device: device), input: input, stats: stats
    ).read()

    #expect(ours.count == expected.planes.count)
    let differences = zip(ours, expected.planes).flatMap {
      zip($0, $1).map { Double(abs($0 - $1)) }
    }
    let mean = differences.reduce(0, +) / Double(differences.count)
    let worst = differences.max() ?? .infinity
    // Measured 2026-10-21: mean 6e-11, max 6e-8 (float32 rounding of the box sums).
    #expect(mean <= 1e-9 && worst <= 1e-6, "mean |Δ| \(mean), max \(worst)")
    // The core really was compressed, or the comparison would prove nothing.
    let drop = zip(image.planes[1], expected.planes[1]).map { Double($0 - $1) }.max() ?? 0
    #expect(drop > 0.002, "hdrcomp lowered the core by only \(drop)")
  }
}
