import CryptoKit
import Foundation
import ImageKit
import TestSupport
import Testing

/// Siril wrote every layer of a legacy run; its `stat` of them (`M31RunLayers`) is the reference
/// ImageKit's reader must agree with. The files themselves stay in `~/Documents/astro/runs`.
@Suite(
  "Live FITS oracle: the M31 run layers against Siril's stat", .liveFixtures,
  .enabled(if: M31RunLayers.folder != nil, "~/Documents/astro/runs/M_31/… absent"),
  .tags(.live), .serialized, .timeLimit(.minutes(5)))
struct LiveFITSOracleTests {
  @Test(
    "dims, per-channel mean/min/max agree with Siril; a rewrite is byte-identical",
    .scratchDirectory, arguments: M31RunLayers.names)
  func testLiveFITS_layerMatchesSiril(_ name: String) throws {
    let manifest = try #require(M31RunLayers.manifest)
    let expected = try #require(manifest.files.first { $0.name == name })
    let url = try #require(M31RunLayers.folder).appendingPathComponent(name)
    let original = try Data(contentsOf: url, options: .mappedIfSafe)
    let digest = SHA256.hash(data: original).map { String(format: "%02x", $0) }.joined()
    try #require(digest == expected.sha256, "\(name) changed since it was recorded: re-record")

    let file = try FITSFile.read(at: url)
    let image = try file.image()
    #expect(image.width == expected.width && image.height == expected.height)
    #expect(image.planes.count == expected.channels.count)
    let slack = manifest.tolerance + 1e-6
    for (plane, siril) in zip(image.planes, expected.channels) {
      let stats = Self.stats(plane, scale: manifest.scale)
      #expect(abs(stats.mean - siril.mean) <= slack, "\(name) mean \(stats.mean) vs \(siril.mean)")
      #expect(abs(stats.min - siril.min) <= slack, "\(name) min \(stats.min) vs \(siril.min)")
      #expect(abs(stats.max - siril.max) <= slack, "\(name) max \(stats.max) vs \(siril.max)")
    }

    let copy = try ScratchDirectory.url.appendingPathComponent(name)
    try file.write(image, to: copy)
    #expect(try Data(contentsOf: copy, options: .mappedIfSafe) == original)
  }

  /// Siril's `stat` on a plane, on its display scale: the mean skips null pixels (exactly 0, the
  /// black borders of a registered stack — Siril's "nullcheck"); min and max cover every pixel.
  static func stats(_ plane: [Float], scale: Double) -> (mean: Double, min: Double, max: Double) {
    var sum = 0.0
    var counted = 0
    var low = Float.greatestFiniteMagnitude
    var high = -Float.greatestFiniteMagnitude
    for value in plane {
      if value != 0 {
        sum += Double(value)
        counted += 1
      }
      low = Swift.min(low, value)
      high = Swift.max(high, value)
    }
    return (sum / Double(max(counted, 1)) * scale, Double(low) * scale, Double(high) * scale)
  }
}
