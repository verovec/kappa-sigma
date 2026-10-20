import Foundation
import StackKit
import TestSupport
import Testing

/// `EdgeCropper` is `applyEdgeCrop` (`edgecrop_test.go` `TestApplyEdgeCrop`): the combine inputs
/// are cut to their common clean field, under another name; the masters stay whole.
@Suite("EdgeCropper — the combine inputs cut to their common clean field")
struct EdgeCropperTests {
  static func inputs(_ filters: [String]) throws -> (URL, [String: String]) {
    let out = try ScratchDirectory.url.appendingPathComponent("out")
    for filter in filters { try PipelineSiril.frame(out.appendingPathComponent("aligned_\(filter).fits")) }
    return (out, Dictionary(uniqueKeysWithValues: filters.map { ($0, "aligned_\($0)") }))
  }

  /// A recorded verdict per file name.
  static func measured(_ rects: [String: EdgeRect], capped: Bool = false) -> EdgeCropper {
    EdgeCropper { url in
      let rect = rects[url.deletingPathExtension().lastPathComponent] ?? EdgeRect(x0: 0, y0: 0, x1: 256, y1: 256)
      return (rect, capped, 256, 256)
    }
  }

  @Test("channels are cut to the intersection; the aligned inputs stay whole", .scratchDirectory)
  func testCommonField() throws {
    let (out, channels) = try Self.inputs(["R", "G"])
    var journal = PreprocessJournal()
    let cropper = Self.measured([
      "aligned_R": EdgeRect(x0: 40, y0: 0, x1: 256, y1: 250), "aligned_G": EdgeRect(x0: 20, y0: 3, x1: 250, y1: 256),
    ])
    let (cropped, crop) = cropper.apply(channels, out: out, journal: &journal)
    #expect(cropped == ["R": "trim_R", "G": "trim_G"])
    #expect(crop?.rect == EdgeRect(x0: 40, y0: 3, x1: 250, y1: 250))
    #expect(crop.map { abs($0.fraction - Double(210 * 247) / Double(256 * 256)) < 1e-12 } == true)
    let trimmed = try String(bytes: Data(contentsOf: out.appendingPathComponent("trim_G.fits")).prefix(2880), encoding: .ascii) ?? ""
    #expect(trimmed.contains("NAXIS1  =                  210") && trimmed.contains("NAXIS2  =                  247"))
    let original = try String(bytes: Data(contentsOf: out.appendingPathComponent("aligned_G.fits")).prefix(2880), encoding: .ascii) ?? ""
    #expect(original.contains("NAXIS1  = 256"))
    #expect(journal.warnings.isEmpty)
  }

  @Test("a clean stack is passed through untouched, with no needless copy", .scratchDirectory)
  func testClean() throws {
    let (out, channels) = try Self.inputs(["RGB"])
    var journal = PreprocessJournal()
    let (passed, crop) = Self.measured([:]).apply(channels, out: out, journal: &journal)
    #expect(passed == channels && crop == nil)
    #expect(!FileManager.default.fileExists(atPath: out.appendingPathComponent("trim_RGB.fits").path))
  }

  @Test("a capped measurement is cut to the cap and says so", .scratchDirectory)
  func testCapped() throws {
    let (out, channels) = try Self.inputs(["L"])
    var journal = PreprocessJournal()
    let cropper = Self.measured(["aligned_L": EdgeRect(x0: 30, y0: 30, x1: 226, y1: 226)], capped: true)
    _ = cropper.apply(channels, out: out, journal: &journal)
    #expect(
      journal.warnings == [
        "the stack's ragged edge reaches past 12% of the frame — trimming that much and no more; "
          + "the sky model may still see a step"
      ])
  }

  @Test("no common field, an unreadable input: combined uncropped, with the reason", .scratchDirectory)
  func testSkipped() throws {
    let (out, channels) = try Self.inputs(["R", "G"])
    var journal = PreprocessJournal()
    let disjoint = Self.measured([
      "aligned_R": EdgeRect(x0: 0, y0: 0, x1: 100, y1: 256), "aligned_G": EdgeRect(x0: 150, y0: 0, x1: 256, y1: 256),
    ])
    #expect(disjoint.apply(channels, out: out, journal: &journal).channels == channels)
    #expect(journal.warnings == ["edge trim skipped: the channels share no clean field"])
    var second = PreprocessJournal()
    let pixels = EdgeCropper()
    #expect(pixels.apply(["X": "absent"], out: out, journal: &second).crop == nil)
    #expect(second.warnings.first?.hasPrefix("edge trim skipped: ") == true)
  }

  @Test("the pixel measurement reads the image itself", .scratchDirectory)
  func testPixels() throws {
    let (out, _) = try Self.inputs(["L"])
    let measured = try EdgeCropper.pixels(out.appendingPathComponent("aligned_L.fits"))
    #expect(measured.width == 256 && measured.height == 256 && !measured.capped)
    #expect(measured.rect == EdgeRect(x0: 0, y0: 0, x1: 256, y1: 256))
  }

  @Test("L+R+G+B, R+G+B, a colour master; nothing else makes a composite", .scratchDirectory)
  func testCombiner() async throws {
    #expect(ChannelCombiner.inputs(["L": "l", "R": "r", "G": "g", "B": "b"]) == .lrgb(lum: "l", r: "r", g: "g", b: "b"))
    #expect(ChannelCombiner.inputs(["R": "r", "G": "g", "B": "b", "Ha": "h"]) == .rgb(r: "r", g: "g", b: "b"))
    #expect(ChannelCombiner.inputs(["RGB": "c"]) == .colour("c"))
    #expect(ChannelCombiner.inputs(["L": "l"]) == nil && ChannelCombiner.inputs(["Ha": "h", "OIII": "o"]) == nil)
    let siril = PipelineSiril()
    let out = try ScratchDirectory.url.appendingPathComponent("out")
    let combined = try await ChannelCombiner(runner: siril.runner).combine(
      ["L": "trim_L", "R": "trim_R", "G": "trim_G", "B": "trim_B"], out: out)
    #expect(combined.map { FileManager.default.fileExists(atPath: $0.path) } == true)
    #expect(siril.calls.map(\.script).last?.hasSuffix("load combined\nsubsky 1\nrmgreen 0\nsave combined\n") == true)
    #expect(try await ChannelCombiner(runner: siril.runner).combine(["L": "l"], out: out) == nil)
  }
}
