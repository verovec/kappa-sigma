import Foundation
import StackKit
import TestSupport
import Testing

/// The trim of a finished stack folder (card 0114): once `bundle.json` is written, the Studio
/// reads only the layers it names, so the other intermediate FITS go; masters, previews, records
/// and sub-folders stay.
@Suite("StackFolder — trimming a finished stack to what its bundle reads")
struct StackFolderTests {
  struct Case: Sendable, CustomTestStringConvertible {
    var name: String
    var layers: [String]
    var removed: [String]
    var testDescription: String { name }
  }

  /// Every file a run can leave at the top of its folder, beside a `history/` the Studio wrote.
  static let files = [
    "aligned_RGB.fits", "aligned_Ha.fits", "combine_RGB.fits", "combined.fits",
    "master_RGB.fits", "master_RGB-dualband.fits", "syn_Ha.fits", "syn_OIII.fits",
    "trim_RGB.fits", "rgb_base.fits", "combined_preview.png", "master_RGB_preview.png",
    "grades.json", "bundle.json", "journal.txt",
  ]

  static let cases = [
    Case(
      name: "a bundle of trim layers", layers: ["trim_RGB.fits"],
      removed: [
        "aligned_Ha.fits", "aligned_RGB.fits", "combine_RGB.fits", "combined.fits",
        "rgb_base.fits", "syn_Ha.fits", "syn_OIII.fits",
      ]),
    Case(
      name: "a bundle naming the combined image", layers: ["combined.fits"],
      removed: [
        "aligned_Ha.fits", "aligned_RGB.fits", "combine_RGB.fits", "rgb_base.fits",
        "syn_Ha.fits", "syn_OIII.fits", "trim_RGB.fits",
      ]),
    Case(
      name: "a colour base and synthetic lines",
      layers: ["rgb_base.fits", "syn_Ha.fits", "syn_OIII.fits"],
      removed: [
        "aligned_Ha.fits", "aligned_RGB.fits", "combine_RGB.fits", "combined.fits",
        "trim_RGB.fits",
      ]),
  ]

  /// The bundle naming `files`, decoded from the JSON a run writes.
  static func bundle(_ files: [String]) throws -> LinearBundle {
    let stats = #"{"bg":0.1,"madn":0.01,"sky":0.1,"snr":10}"#
    let layers = files.map {
      #"{"id":"\#($0)","role":"rgb","file":"\#($0)","source":"trim","stats":\#(stats)}"#
    }
    let json = #"""
      {"version":1,"run_id":"R1","color_model":"osc","grid":{"width":4,"height":4},
      "layers":[\#(layers.joined(separator: ","))]}
      """#
    return try JSONDecoder().decode(LinearBundle.self, from: Data(json.utf8))
  }

  @Test(
    "only the FITS the bundle does not name go, masters kept", .scratchDirectory,
    arguments: cases)
  func testTrimKeepsBundleLayersAndMasters(_ row: Case) throws {
    let folder = try ScratchDirectory.url.appendingPathComponent("stacks/R1", isDirectory: true)
    let history = folder.appendingPathComponent("history", isDirectory: true)
    try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
    try Data(count: 64).write(to: history.appendingPathComponent("step_1.fits"))
    // A folder named like a FITS is not a file of the run: kept.
    try FileManager.default.createDirectory(
      at: folder.appendingPathComponent("odd.fits"), withIntermediateDirectories: true)
    for (index, name) in Self.files.enumerated() {
      try Data(count: 10 + index).write(to: folder.appendingPathComponent(name))
    }

    let trimmed = try StackFolder.trim(folder, bundle: try Self.bundle(row.layers))

    #expect(trimmed.map(\.name) == row.removed)
    #expect(trimmed.allSatisfy { $0.bytes > 0 })
    let left = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    let kept = Set(Self.files).subtracting(row.removed).union(["history", "odd.fits"])
    #expect(left == kept.sorted())
    let step = history.appendingPathComponent("step_1.fits")
    #expect(FileManager.default.fileExists(atPath: step.path))
  }

  @Test("a bundle naming a layer outside its folder trims nothing", .scratchDirectory)
  func testTrimRefusesForeignLayer() throws {
    let folder = try ScratchDirectory.url.appendingPathComponent("stacks/R1", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data(count: 8).write(to: folder.appendingPathComponent("aligned_RGB.fits"))
    #expect(throws: StackFolder.Refusal.self) {
      try StackFolder.trim(folder, bundle: try Self.bundle(["../other/trim_RGB.fits"]))
    }
    let aligned = folder.appendingPathComponent("aligned_RGB.fits")
    #expect(FileManager.default.fileExists(atPath: aligned.path))
  }
}
