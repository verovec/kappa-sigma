import Foundation
import StackKit
import TestSupport
import Testing

/// The linear bundle: the run's layers on one grid with full-resolution stats (card 0048 schema
/// `{version, run_id, color_model, grid, layers[{id, role, file, source, stats{bg, madn, sky,
/// snr}, continuum_k?}]}`).
@Suite("Bundle — the linear layers a run hands to the Studio")
struct BundleTests {
  /// A 64×64 layer: a ramp of sky plus a few bright pixels, so median ≠ mean.
  static func layer(_ name: String, in folder: URL, offset: UInt16, size: Int = 64) throws -> URL {
    let pixels = (0..<size * size).map { index -> UInt16 in
      index % 97 == 0 ? 60000 : offset + UInt16(index % 200)
    }
    return try TestFITS.write(name, in: folder, width: size, height: size, planes: [pixels], cards: [:])
  }

  @Test(
    "schema fields present, stats within 1% of a direct median; mixed dims refused, no file",
    .scratchDirectory)
  func testWriteAndRefuseMixedDims() throws {
    let folder = try ScratchDirectory.url.appendingPathComponent("linear")
    let lum = try Self.layer("trim_L.fits", in: folder, offset: 1000)
    _ = try Self.layer("trim_Ha.fits", in: folder, offset: 3000)
    let bundle = try BundleWriter().write(
      runID: "R1", colorModel: .mono,
      layers: [
        .init(filter: "L", file: lum, source: "trim"),
        .init(filter: "Ha", file: folder.appendingPathComponent("trim_Ha.fits"), source: "trim"),
      ],
      to: folder)

    let json = try JSONSerialization.jsonObject(
      with: Data(contentsOf: folder.appendingPathComponent("bundle.json"))) as? [String: Any]
    let object = try #require(json)
    #expect(Set(object.keys) == ["version", "run_id", "color_model", "grid", "layers"])
    #expect(object["run_id"] as? String == "R1" && object["color_model"] as? String == "mono")
    #expect((object["grid"] as? [String: Int]) == ["width": 64, "height": 64])
    let layers = try #require(object["layers"] as? [[String: Any]])
    #expect(layers.map { $0["role"] as? String } == ["lum", "line"])
    #expect(layers.map { $0["file"] as? String } == ["trim_L.fits", "trim_Ha.fits"])
    #expect(Set((layers[0]["stats"] as? [String: Double])?.keys ?? [:].keys) == ["bg", "madn", "sky", "snr"])

    let values = (0..<4096).map { (index: Int) -> Double in
      let ramp = Double(index % 200)
      return index % 97 == 0 ? 60000 : 1000 + ramp
    }
    let direct = values.sorted()[values.count / 2]
    let stats = try #require(bundle.layers.first?.stats)
    #expect(abs(stats.bg - direct) <= 0.01 * direct)
    #expect(stats.madn > 0 && stats.sky <= stats.bg && stats.snr > 0)
    #expect(try BundleWriter.read(from: folder) == bundle)
    try Self.refuseMixedDims(in: try ScratchDirectory.url.appendingPathComponent("mixed"))
  }

  /// Mixed dimensions are a typed error and no file.
  static func refuseMixedDims(in folder: URL) throws {
    let big = try Self.layer("trim_R.fits", in: folder, offset: 100)
    let small = try Self.layer("trim_G.fits", in: folder, offset: 100, size: 32)
    #expect(throws: PreprocessError.mixedDimensions(["R 64×64", "G 32×32"])) {
      try BundleWriter().write(
        runID: "R1", colorModel: .mono,
        layers: [.init(filter: "R", file: big, source: "trim"), .init(filter: "G", file: small, source: "trim")],
        to: folder)
    }
    #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("bundle.json").path))
  }

  @Test("each filter has its role; a colour master is rgb", arguments: [
    ("L", "lum"), ("R", "red"), ("G", "green"), ("B", "blue"), ("Ha", "line"), ("OIII", "line"),
    ("SII", "line"), ("RGB", "rgb"), ("Custom", "line"),
  ])
  func testRoles(filter: String, role: String) {
    #expect(LinearBundle.Role(filter: filter).rawValue == role)
  }
}
