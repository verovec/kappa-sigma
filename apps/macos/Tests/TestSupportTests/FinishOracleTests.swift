import Foundation
import TestSupport
import Testing

@Suite("FinishOracle: the recorded v9 finishing chain of run #78, verified by its manifest")
struct FinishOracleTests {
  @Test("the committed manifest lists every stage the E12/E13 cards use, with flags and hashes")
  func testManifestDecodesAndIsComplete() throws {
    let manifest = try FinishOracle.manifest()
    #expect(Set(manifest.stages.map(\.name)).isSuperset(of: FinishOracle.requiredStages))
    for stage in manifest.stages {
      #expect(!stage.tool.isEmpty, "\(stage.name): tool")
      #expect(stage.tool == "starnet2" || !stage.flags.isEmpty, "\(stage.name): flags")
      // Flags are the stage's settings only; inputs and outputs are listed apart.
      #expect(
        stage.flags.allSatisfy { !["-in", "-out", "-base", "-ha", "-oiii"].contains($0) },
        "\(stage.name): I/O in flags")
      #expect(
        Set(stage.outputs.map(\.variant)) == ["full", "crop"], "\(stage.name): both variants")
      for file in stage.outputs {
        #expect(file.sha256.count == 64 && file.width > 0 && file.height > 0, "\(file.path)")
      }
    }
    #expect(manifest.provenance.run == "M_31/20261018_191749")
    #expect(manifest.crop == FinishManifest.Crop(x: 2471, y: 1497, width: 1024, height: 768))
    #expect(manifest.toolFiles.allSatisfy { $0.sha256.count == 64 })
    #expect(
      Set(manifest.validated.map(\.stage))
        == ["haplus_final", "starless", "stars_25", "stars_50", "stars_75"])
    #expect(manifest.tolerance.maxAbs <= 1.0 / 255 && manifest.tolerance.meanAbs <= 1.0 / 255)
  }

  @Test("the oracle is found only with fixtures/finish and live suites on", .scratchDirectory)
  func testSkipsWhenAbsent() throws {
    let home = try ScratchDirectory.url
    #expect(FinishOracle.root(home: home) == nil, "empty HOME: skip")
    let fixtures = home.appendingPathComponent("Documents/astro/fixtures", isDirectory: true)
    try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
    #expect(FinishOracle.root(home: home) == nil, "fixtures without finish/: skip")
    let finish = fixtures.appendingPathComponent("finish", isDirectory: true)
    try FileManager.default.createDirectory(at: finish, withIntermediateDirectories: true)
    #expect(FinishOracle.root(home: home)?.standardizedFileURL == finish.standardizedFileURL)
    #expect(FinishOracle.root(home: home, environment: ["ASTROSTACK_SKIP_LIVE": "1"]) == nil)
  }

  @Test(
    "verify reports every changed, missing, unreadable or resized file; tools by hash only",
    .scratchDirectory)
  func testVerifyDetectsDrift() throws {
    let root = try ScratchDirectory.url
    let png = try Self.writePNG(width: 3, height: 2, at: root.appendingPathComponent("crop/a.png"))
    let fits = try Self.writeFITSHeader(
      width: 5, height: 4, at: root.appendingPathComponent("crop/b.FITS"))
    let tool = root.appendingPathComponent("tools-src/main.go")
    try FileManager.default.createDirectory(
      at: tool.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("package main".utf8).write(to: tool)
    let broken = root.appendingPathComponent("crop/broken.png")
    try Data("not a png".utf8).write(to: broken)
    let files = [
      FinishManifest.File(
        path: "crop/a.png", sha256: try FinishOracle.sha256(of: png), width: 3, height: 2),
      FinishManifest.File(
        path: "crop/b.FITS", sha256: try FinishOracle.sha256(of: fits), width: 5, height: 4),
      FinishManifest.File(
        path: "tools-src/main.go", sha256: try FinishOracle.sha256(of: tool), width: 0, height: 0),
    ]
    #expect(FinishOracle.verify(files, root: root).isEmpty)

    let wrong = [
      FinishManifest.File(
        path: "crop/a.png", sha256: String(repeating: "0", count: 64), width: 3, height: 2),
      FinishManifest.File(path: "crop/b.FITS", sha256: files[1].sha256, width: 6, height: 4),
      FinishManifest.File(
        path: "crop/broken.png", sha256: try FinishOracle.sha256(of: broken), width: 3, height: 2),
      FinishManifest.File(path: "crop/missing.png", sha256: files[0].sha256, width: 3, height: 2),
    ]
    let problems = FinishOracle.verify(wrong, root: root)
    #expect(problems.count == 4, "every file reported, none aborts the check")
    #expect(problems[0] == "crop/a.png: sha256 differs")
    #expect(problems[1] == "crop/b.FITS: 5×4, manifest says 6×4")
    #expect(problems[2].hasPrefix("crop/broken.png: unreadable"))
    #expect(problems[3] == "crop/missing.png: missing")
  }

  @Test("the difference of two images is measured in fractions of full scale", .scratchDirectory)
  func testDifference() throws {
    let root = try ScratchDirectory.url
    let grey = try Self.writePNG(width: 4, height: 2, at: root.appendingPathComponent("a.png"))
    let lighter = root.appendingPathComponent("b.png")
    try FinishImages.writeTestPNG(width: 4, height: 2, value: 129, to: lighter)
    #expect(try FinishImages.difference(grey, grey) == (0, 0))
    let delta = try FinishImages.difference(grey, lighter)
    // Grey is converted to sRGB on reading: one grey level is about, not exactly, 1/255.
    #expect(delta.meanAbs > 0.5 / 255 && delta.meanAbs < 1.5 / 255)
    #expect(abs(delta.maxAbs - delta.meanAbs) < 1e-9, "a uniform step: max = mean")
    let small = root.appendingPathComponent("c.png")
    try FinishImages.writeTestPNG(width: 2, height: 2, to: small)
    #expect(throws: FinishOracleError.self) { try FinishImages.difference(grey, small) }
  }

  static func writePNG(width: Int, height: Int, at url: URL) throws -> URL {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FinishImages.writeTestPNG(width: width, height: height, to: url)
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

/// The recorded files themselves and the PO's deliverables: live, skipped without the folder.
@Suite(
  "Live finish oracle files", .liveFixtures, .finishOracle, .tags(.live), .serialized,
  .timeLimit(.minutes(5)))
struct LiveFinishOracleTests {
  @Test("every recorded file and tool source matches its manifest hash and size")
  func testLiveFilesMatchManifest() throws {
    let root = try #require(FinishOracle.root)
    let manifest = try FinishOracle.manifest()
    #expect(FinishOracle.verify(manifest.allFiles + manifest.toolFiles, root: root) == [])
  }

  @Test("the full-frame renders reproduce the PO's validated run #78 deliverables")
  func testRendersMatchDeliverables() throws {
    let root = try #require(FinishOracle.root)
    let manifest = try FinishOracle.manifest()
    let home = FileManager.default.homeDirectoryForCurrentUser
    let run = try #require(FinishOracle.runFolder(manifest, home: home), "run #78 absent")
    for entry in manifest.validated {
      let deliverable = run.appendingPathComponent(entry.deliverable)
      #expect(try FinishOracle.sha256(of: deliverable) == entry.sha256, "\(entry.deliverable)")
      let render = try #require(
        manifest.stages.first { $0.name == entry.stage }?.outputs.first { $0.variant == "full" })
      let delta = try FinishImages.difference(root.appendingPathComponent(render.path), deliverable)
      #expect(delta.meanAbs <= manifest.tolerance.meanAbs, "\(entry.stage) mean \(delta.meanAbs)")
      #expect(delta.maxAbs <= manifest.tolerance.maxAbs, "\(entry.stage) max \(delta.maxAbs)")
    }
  }
}
