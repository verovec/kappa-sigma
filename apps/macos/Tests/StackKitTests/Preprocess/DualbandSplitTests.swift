import FilterKit
import Foundation
import ImageKit
import StackKit
import TestSupport
import Testing

/// `DualbandSplit` is `splitDuoband` + `dualSetChannels` (`duoband.go`, `filtersetlanes.go`):
/// cases of `duoband_test.go` (`TestSplitDuoband*`) and `dualsetchannels_test.go`.
@Suite("DualbandSplit — the registered dual-band master becomes pseudo-Hα and pseudo-[OIII]")
struct DualbandSplitTests {
  /// A 4 × 3 three-plane master at `out/name.fits` of constant r, g, b.
  @discardableResult
  static func master(_ name: String, _ r: Float, _ g: Float, _ b: Float, in out: URL) throws
    -> URL
  {
    try FloatFITS.write(
      out.appendingPathComponent(name + ".fits"), width: 4, height: 3,
      planes: [r, g, b].map { [Float](repeating: $0, count: 12) })
  }

  static func value(_ url: URL) throws -> (planes: Int, first: Float) {
    let planes = try FITSFile.read(at: url).image().planes
    return (planes.count, planes[0][0])
  }

  @Test(
    "Hα is the red plane, [OIII] the max of green and blue (never their mean)",
    .scratchDirectory,
    arguments: [
      (Float(0.40), Float(0.20), Float(0.10), Float(0.40), Float(0.20)),
      (0.40, 0.10, 0.25, 0.40, 0.25),
      (0.9, 0.3, 0.3, 0.9, 0.3),
    ])
  func testSplit(r: Float, g: Float, b: Float, ha: Float, oiii: Float) throws {
    let out = try ScratchDirectory.url
    let names = try DualbandSplit.split(
      try Self.master("master_RGB", r, g, b, in: out), out: out, lines: (.hydrogenAlpha, .oxygenIII)
    )
    #expect(names == ("syn_Ha", "syn_OIII"))
    let (haPlanes, haValue) = try Self.value(out.appendingPathComponent("syn_Ha.fits"))
    let (oiiiPlanes, oiiiValue) = try Self.value(out.appendingPathComponent("syn_OIII.fits"))
    #expect(haPlanes == 1 && oiiiPlanes == 1 && haValue == ha && oiiiValue == oiii)
  }

  @Test("a one-plane master cannot be separated", .scratchDirectory)
  func testNeedsThreePlanes() throws {
    let out = try ScratchDirectory.url
    let mono = try FloatFITS.write(
      out.appendingPathComponent("mono.fits"), width: 4, height: 3,
      planes: [[Float](repeating: 0, count: 12)])
    #expect {
      _ = try DualbandSplit.split(mono, out: out, lines: (.hydrogenAlpha, .oxygenIII))
    } throws: { "\($0)".contains("need 3") }
  }

  @Test("the lane is consumed: broadband base kept, Hα and [OIII] added, a note", .scratchDirectory)
  func testChannels() throws {
    let out = try ScratchDirectory.url
    try Self.master("aligned_RGB", 0.5, 0.5, 0.5, in: out)
    try Self.master("aligned_RGB-dualband", 0.40, 0.20, 0.10, in: out)
    try Self.master("master_RGB-dualband", 0.99, 0.99, 0.99, in: out)
    let (channels, note) = DualbandSplit.channels(
      ["RGB": "aligned_RGB", "RGB-dualband": "aligned_RGB-dualband"], out: out)
    #expect(channels == ["RGB": "aligned_RGB", "Ha": "syn_Ha", "OIII": "syn_OIII"])
    #expect(note?.hasPrefix("mixed filter sets") == true)
    // The REGISTERED master is split, never the raw one.
    #expect(try Self.value(out.appendingPathComponent("syn_Ha.fits")).first == 0.40)
  }

  @Test("without a dual-band lane the map is returned as is, silently", .scratchDirectory)
  func testNoLane() throws {
    let (channels, note) = DualbandSplit.channels(
      ["L": "aligned_L", "R": "aligned_R"], out: try ScratchDirectory.url)
    #expect(channels == ["L": "aligned_L", "R": "aligned_R"] && note == nil)
  }

  @Test("an unsplittable lane is dropped; the broadband base still finishes", .scratchDirectory)
  func testUnsplittable() throws {
    let out = try ScratchDirectory.url
    try Self.master("aligned_RGB", 0.5, 0.5, 0.5, in: out)
    let (channels, note) = DualbandSplit.channels(
      ["RGB": "aligned_RGB", "RGB-dualband": "missing_master"], out: out)
    #expect(channels == ["RGB": "aligned_RGB"] && note?.contains("skipped") == true)
  }

  @Test("an unregistered dual-band master is never split over the base", .scratchDirectory)
  func testUnregistered() throws {
    let out = try ScratchDirectory.url
    try Self.master("master_RGB", 0.5, 0.5, 0.5, in: out)
    try Self.master("master_RGB-dualband", 0.40, 0.20, 0.10, in: out)
    let (channels, note) = DualbandSplit.channels(
      ["RGB": "master_RGB", "RGB-dualband": "master_RGB-dualband"], out: out, registered: false)
    #expect(channels == ["RGB": "master_RGB"] && note?.contains("not registered") == true)
    #expect(!FileManager.default.fileExists(atPath: out.appendingPathComponent("syn_Ha.fits").path))
  }

  @Test("no broadband master left: the lane becomes the colour channel, unsplit", .scratchDirectory)
  func testNoBroadbandBase() throws {
    let out = try ScratchDirectory.url
    try Self.master("aligned_RGB-dualband", 0.40, 0.20, 0.10, in: out)
    let (channels, note) = DualbandSplit.channels(
      ["RGB-dualband": "aligned_RGB-dualband"], out: out)
    #expect(channels == ["RGB": "aligned_RGB-dualband"] && note?.contains("broadband") == true)
    #expect(!FileManager.default.fileExists(atPath: out.appendingPathComponent("syn_Ha.fits").path))
  }

  @Test("another clip's pair names the layers after its lines", .scratchDirectory)
  func testSplitNamesFollowTheLines() throws {
    let out = try ScratchDirectory.url
    let names = try DualbandSplit.split(
      try Self.master("master_RGB", 0.4, 0.2, 0.1, in: out), out: out,
      lines: (.sulfurII, .oxygenIII))
    #expect(names == ("syn_SII", "syn_OIII"))
    #expect(FileManager.default.fileExists(atPath: out.appendingPathComponent("syn_SII.fits").path))
  }
}
