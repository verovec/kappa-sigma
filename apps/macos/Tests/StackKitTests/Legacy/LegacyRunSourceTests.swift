import Foundation
import ImageKit
import ProjectKit
import StackKit
import TestSupport
import Testing

/// Builds legacy run folders as the Go engine left them: small float32 layers, `run.json`
/// channels and `stages.json`.
enum LegacyRunFixture {
  static func make(
    in folder: URL, files: [String], sizes: [String: (Int, Int)] = [:],
    channels: [(filter: String, frames: Int)] = [], color: String = "osc"
  ) throws -> URL {
    let run = folder.appendingPathComponent("20261018_191749")
    try FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)
    for file in files {
      let (width, height) = sizes[file] ?? (4, 3)
      let planes = file.hasPrefix("rgb") || file.contains("RGB") ? 3 : 1
      let header = try FITSFile.parse(Data(("END" + String(repeating: " ", count: 2877)).utf8))
        .header
      let image = AstroImage(
        width: width, height: height,
        planes: (0..<planes).map { plane in (0..<width * height).map { Float($0 + plane) / 100 } },
        metadata: ImageMetadata(header: header))
      try FITSFile.create(image, keeping: nil, at: run.appendingPathComponent(file + ".fits"))
    }
    let channelJSON = channels.map { channel in
      """
      {"object": "M_31", "filter": "\(channel.filter)", "exposure_ms": 300000,
       "input_frames": \(channel.frames + 2), "stacked_frames": \(channel.frames)}
      """
    }.joined(separator: ", ")
    let runJSON = #"{"object": "M_31", "run_id": "20261018_191749", "channels": [\#(channelJSON)]}"#
    try Data(runJSON.utf8).write(to: run.appendingPathComponent("run.json"))
    let stages = """
      {"run_id": "20261018_191749", "mode": "deepsky",
       "preset": {"Mode": "deepsky", "Color": "\(color)"}}
      """
    try Data(stages.utf8).write(to: run.appendingPathComponent("stages.json"))
    return run
  }
}

@Suite("LegacyRunSource: a finished legacy run opened read-only as a bundle")
struct LegacyRunSourceTests {
  struct Case: Sendable, CustomTestStringConvertible {
    let name: String
    let files: [String]
    /// id → (role, file, source)
    let expected: [String: String]
    var testDescription: String { name }
  }

  @Test(
    "layers by the legacy precedence: combine_ > aligned_ > master_ > syn_, rgb_base as the base",
    .scratchDirectory,
    arguments: [
      Case(
        name: "combine wins", files: ["combine_Ha", "aligned_Ha", "master_Ha", "syn_Ha"],
        expected: ["Ha": "line combine_Ha.fits combine"]),
      Case(
        name: "aligned over master", files: ["aligned_L", "master_L"],
        expected: ["L": "lum aligned_L.fits aligned"]),
      Case(name: "master alone", files: ["master_R"], expected: ["R": "red master_R.fits master"]),
      Case(
        name: "dual-band OSC run",
        files: [
          "rgb_base", "aligned_RGB", "master_RGB", "aligned_RGB-dualband", "syn_Ha", "syn_OIII",
        ],
        expected: [
          "RGB": "rgb rgb_base.fits rgb_base", "Ha": "line syn_Ha.fits syn",
          "OIII": "line syn_OIII.fits syn",
        ]),
      Case(
        name: "no base: the colour channel's best file", files: ["aligned_RGB", "master_RGB"],
        expected: ["RGB": "rgb aligned_RGB.fits aligned"]),
    ])
  func testDiscoverLayersPrecedence(_ row: Case) throws {
    let run = try LegacyRunFixture.make(in: ScratchDirectory.url, files: row.files)
    let source = try LegacyRunSource(folder: run)
    let found = Dictionary(
      uniqueKeysWithValues: source.layers.map {
        ($0.id, "\($0.role.rawValue) \($0.file) \($0.source)")
      })
    #expect(found == row.expected)
  }

  @Test(
    "frames come from run.json: the dual-band channel's count for its synthetic lines",
    .scratchDirectory)
  func testFramesFromRunJSON() throws {
    let run = try LegacyRunFixture.make(
      in: ScratchDirectory.url, files: ["rgb_base", "aligned_RGB-dualband", "syn_Ha", "syn_OIII"],
      channels: [("RGB", 76), ("RGB-dualband", 34)])
    let source = try LegacyRunSource(folder: run)
    #expect(source.layers.map(\.id) == ["RGB", "Ha", "OIII"])
    #expect(source.layers.map(\.frames) == [76, 34, 34])
    #expect(source.runID == "20261018_191749" && source.object == "M_31")
    #expect(source.colorModel == .osc)
    #expect(source.grid.width == 4 && source.grid.height == 3)
  }

  @Test("layers of different sizes are refused, naming every layer and its size", .scratchDirectory)
  func testRefusesMixedDims() throws {
    let run = try LegacyRunFixture.make(
      in: ScratchDirectory.url, files: ["rgb_base", "syn_Ha", "syn_OIII"],
      sizes: ["syn_OIII": (5, 3)])
    #expect(throws: LegacyRunError.mixedDimensions(["RGB 4×3", "Ha 4×3", "OIII 5×3"])) {
      try LegacyRunSource(folder: run)
    }
  }

  @Test("a run with no layer, or without run.json, is a typed error", .scratchDirectory)
  func testRefusesEmptyRuns() throws {
    let empty = try LegacyRunFixture.make(in: ScratchDirectory.url, files: [])
    #expect(throws: LegacyRunError.noLayers(empty.path)) { try LegacyRunSource(folder: empty) }
    try FileManager.default.removeItem(at: empty.appendingPathComponent("run.json"))
    #expect(throws: LegacyRunError.self) { try LegacyRunSource(folder: empty) }
  }

  @Test(
    "a read-only copy opens, builds its bundle, and the project records only its path",
    .scratchDirectory)
  func testReadOnlyDirOpens() throws {
    let scratch = try ScratchDirectory.url
    let run = try LegacyRunFixture.make(in: scratch, files: ["rgb_base", "syn_Ha", "syn_OIII"])
    try Self.setWritable(false, run)
    defer { try? Self.setWritable(true, run) }

    let source = try LegacyRunSource(folder: run)
    let bundle = try LinearBundle.build(fromLegacyRun: source)
    #expect(bundle.layers.map(\.id) == ["RGB", "Ha", "OIII"])
    #expect(bundle.grid.width == 4 && bundle.grid.height == 3)
    #expect(bundle.layers.allSatisfy { $0.stats.madn > 0 })
    #expect(
      try FileManager.default.contentsOfDirectory(atPath: run.path).count == 5, "nothing written")

    let project = try ProjectPackage.create(at: scratch.appendingPathComponent("M31.astrostack"))
    defer { try? project.close() }
    let recorded = try source.record(in: project.store)
    #expect(recorded.kind == .legacyRun && recorded.path == run.standardizedFileURL.path)
    #expect(recorded.readOnly)
  }

  @Test(
    "a bundle.json in the run (made by this app) is used instead of discovery",
    .scratchDirectory)
  func testPrefersBundleWhenPresent() throws {
    let run = try LegacyRunFixture.make(
      in: ScratchDirectory.url, files: ["trim_L", "aligned_L", "syn_Ha"], color: "mono")
    let written = try BundleWriter().write(
      runID: "20261018_191749", colorModel: .mono,
      layers: [
        BundleWriter.Input(
          filter: "L", file: run.appendingPathComponent("trim_L.fits"), source: "trim")
      ],
      to: run)
    let source = try LegacyRunSource(folder: run)
    #expect(source.bundle == written)
    #expect(source.layers.map(\.id) == ["L"], "the bundle's layers, not discovery's (no Ha)")
    #expect(try LinearBundle.build(fromLegacyRun: source) == written)
  }

  static func setWritable(_ writable: Bool, _ folder: URL) throws {
    let mode: Int16 = writable ? 0o755 : 0o555
    let fileMode: Int16 = writable ? 0o644 : 0o444
    for name in try FileManager.default.contentsOfDirectory(atPath: folder.path) {
      try FileManager.default.setAttributes(
        [.posixPermissions: fileMode], ofItemAtPath: folder.appendingPathComponent(name).path)
    }
    try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: folder.path)
  }
}
