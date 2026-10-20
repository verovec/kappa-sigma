import Foundation
import StackKit
import TestSupport
import Testing

/// A split capture's channel alignment (`alignChannels` + `AlignMastersRefScript`): the broadband
/// master leads and is pinned as the reference, one pass (`-2pass` would override the pin).
@Suite("ChannelAligner lanes — the dual-band master resampled onto the broadband grid")
struct ChannelAlignerLaneTests {
  @Test("the pinned-reference script, byte for byte as the legacy builder wrote it")
  func testScript() {
    #expect(
      SirilScripts.alignMastersReference(seq: "ch").render()
        == "requires 1.2.0\nsetext fits\nset32bits\nlink ch -out=.\nsetref ch 1\nregister ch\n"
        + "seqapplyreg ch -framing=min\n")
  }

  @Test("RGB leads, RGB-dualband follows, registered on the pinned reference", .scratchDirectory)
  func testLaneAlignment() async throws {
    let siril = PipelineSiril()
    let (aligned, _) = try await ChannelAlignerTests.align(siril, ["RGB-dualband", "RGB"])
    #expect(aligned == ["RGB": "aligned_RGB", "RGB-dualband": "aligned_RGB-dualband"])
    let joint = try #require(siril.calls.first { $0.directory.lastPathComponent == "04_aligned" })
    #expect(joint.script.contains("setref ch 1\nregister ch\n"))
    let links = try PipelineSiril.links(in: joint.directory)
    #expect(links.first == "0_RGB.fits" && links.last == "1_RGB-dualband.fits")
  }

  @Test("an unsplit run keeps the two-pass joint registration", .scratchDirectory)
  func testUnsplit() async throws {
    let siril = PipelineSiril()
    _ = try await ChannelAlignerTests.align(siril, ["L", "R"])
    #expect(siril.calls.contains { $0.script.contains("register ch -2pass") })
  }
}
