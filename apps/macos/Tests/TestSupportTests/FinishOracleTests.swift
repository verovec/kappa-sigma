import Foundation
import TestSupport
import Testing

@Suite("FinishOracle: the recorded v9 finishing chain of run #78, verified by its manifest")
struct FinishOracleTests {
  @Test("the committed manifest lists every stage the E12/E13 cards use, with flags and hashes")
  func testManifestDecodesAndIsComplete() throws {
    let manifest = try FinishOracle.manifest()
    let names = Set(manifest.stages.map(\.name))
    #expect(names.isSuperset(of: FinishOracle.requiredStages))
    for stage in manifest.stages {
      #expect(!stage.tool.isEmpty, "\(stage.name): tool")
      #expect(stage.tool == "starnet2" || !stage.flags.isEmpty, "\(stage.name): flags")
      #expect(
        Set(stage.outputs.map(\.variant)) == ["full", "crop"], "\(stage.name): both variants")
      for file in stage.outputs {
        #expect(file.sha256.count == 64 && file.width > 0 && file.height > 0, "\(file.path)")
      }
    }
    #expect(manifest.provenance.run == "M_31/20261018_191749")
    #expect(manifest.crop == FinishManifest.Crop(x: 2612, y: 1704, width: 1024, height: 768))
  }

  @Test("HOME without the fixtures folder: no root, the live suite skips", .scratchDirectory)
  func testSkipsWhenAbsent() throws {
    #expect(FinishOracle.root(home: try ScratchDirectory.url) == nil)
  }

  @Test(
    "verify reports a changed file and wrong dimensions, and passes a faithful folder",
    .scratchDirectory)
  func testVerifyDetectsDrift() throws {
    let root = try ScratchDirectory.url
    let png = try Self.writePNG(width: 3, height: 2, at: root.appendingPathComponent("crop/a.png"))
    let fits = try Self.writeFITSHeader(
      width: 5, height: 4, at: root.appendingPathComponent("crop/b.fits"))
    let files = [
      FinishManifest.File(
        path: "crop/a.png", sha256: try FinishOracle.sha256(of: png), width: 3, height: 2),
      FinishManifest.File(
        path: "crop/b.fits", sha256: try FinishOracle.sha256(of: fits), width: 5, height: 4),
    ]
    #expect(try FinishOracle.verify(files, root: root).isEmpty)

    let wrong = [
      FinishManifest.File(
        path: "crop/a.png", sha256: String(repeating: "0", count: 64), width: 3, height: 2),
      FinishManifest.File(path: "crop/b.fits", sha256: files[1].sha256, width: 6, height: 4),
      FinishManifest.File(path: "crop/missing.png", sha256: files[0].sha256, width: 3, height: 2),
    ]
    #expect(
      try FinishOracle.verify(wrong, root: root) == [
        "crop/a.png: sha256 differs", "crop/b.fits: 5×4, manifest says 6×4",
        "crop/missing.png: missing",
      ])
  }

  static func writePNG(width: Int, height: Int, at url: URL) throws -> URL {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FinishOracle.writeTestPNG(width: width, height: height, to: url)
    return url
  }

  static func writeFITSHeader(width: Int, height: Int, at url: URL) throws -> URL {
    func card(_ key: String, _ value: String) -> String {
      (key.padding(toLength: 8, withPad: " ", startingAt: 0) + "= " + value)
        .padding(toLength: 80, withPad: " ", startingAt: 0)
    }
    var text =
      [
        card("SIMPLE", "T"), card("BITPIX", "-32"), card("NAXIS", "2"),
        card("NAXIS1", "\(width)"), card("NAXIS2", "\(height)"),
      ].joined() + "END"
    while text.utf8.count % 2880 != 0 { text += " " }
    try Data(text.utf8).write(to: url)
    return url
  }
}

/// The recorded files themselves: live, skipped where `~/Documents/astro/fixtures/finish` is absent.
@Suite("Live finish oracle files", .finishOracle, .tags(.live))
struct LiveFinishOracleTests {
  @Test("every recorded file matches its manifest hash and dimensions")
  func testLiveFilesMatchManifest() throws {
    let root = try #require(FinishOracle.root)
    let files = try FinishOracle.manifest().allFiles
    #expect(try FinishOracle.verify(files, root: root) == [])
  }
}
