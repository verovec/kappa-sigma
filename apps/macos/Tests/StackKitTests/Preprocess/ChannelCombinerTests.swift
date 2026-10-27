import Foundation
import StackKit
import TestSupport
import Testing

/// What a run's masters combine into (card 0137): a colour composite when the channels make one,
/// else one mono master copied as `combined` — never nothing for a run that stacked something.
@Suite("ChannelCombiner — a combined image for every run")
struct ChannelCombinerTests {
  // A colour master beside a broadband layer is a mixed run, refused before it starts: no
  // composite is guessed for it. The mono order is palette.go's resolveMono, ported as is: L, then Hα, then the canonical
  // order — so OIII + SII is OIII, and R + G + Hα (no B) is Hα, not R.
  @Test(
    "the combine inputs of each channel set",
    arguments: [
      (["L": "l", "R": "r", "G": "g", "B": "b"], .lrgb(lum: "l", r: "r", g: "g", b: "b")),
      (["R": "r", "G": "g", "B": "b"], .rgb(r: "r", g: "g", b: "b")),
      (["RGB": "c", "Ha": "h", "OIII": "o"], .colour("c")),
      (["RGB": "c", "L": "l"], nil),
      (["L": "l", "Ha": "h"], .mono(filter: "L", master: "l")),
      (["Ha": "h"], .mono(filter: "Ha", master: "h")),
      (["SII": "s", "Ha": "h", "OIII": "o"], .mono(filter: "Ha", master: "h")),
      (["OIII": "o", "SII": "s"], .mono(filter: "OIII", master: "o")),
      (["R": "r", "G": "g", "Ha": "h"], .mono(filter: "Ha", master: "h")),
      ([:], nil),
    ] as [([String: String], SirilScripts.CombineInputs?)])
  func testInputs(channels: [String: String], expected: SirilScripts.CombineInputs?) {
    #expect(ChannelCombiner.inputs(channels) == expected)
  }

  @Test("the mono combine loads the master and flattens its sky: no green removal")
  func testMonoScript() throws {
    let url = try #require(
      Bundle.module.url(forResource: "mono", withExtension: "ssf", subdirectory: "Fixtures/combine")
    )
    let recorded = try String(contentsOf: url, encoding: .utf8)
    #expect(
      SirilScripts.combine(.mono(filter: "L", master: "trim_L"), backgroundDegree: 1).render()
        == recorded)
  }

  @Test("the journal says which master a mono combined image is")
  func testNote() {
    #expect(
      ChannelCombiner.note(ChannelCombiner.inputs(["L": "trim_L", "Ha": "trim_Ha"]))
        == "combined = L alone (mono: no colour composite to build)")
    #expect(
      ChannelCombiner.note(ChannelCombiner.inputs(["OIII": "trim_OIII", "SII": "trim_SII"]))
        == "combined = OIII alone (mono: no colour composite to build)")
    #expect(ChannelCombiner.note(.colour("trim_RGB")) == nil)
    #expect(ChannelCombiner.note(nil) == nil)
  }

  @Test("a mono run writes combined.fits with one Siril script", .scratchDirectory)
  func testMonoCombine() async throws {
    let siril = PipelineSiril()
    let out = try ScratchDirectory.url.appendingPathComponent("out")
    let combined = try await ChannelCombiner(runner: siril.runner).combine(
      ["L": "trim_L", "Ha": "trim_Ha"], out: out)
    #expect(combined?.lastPathComponent == "combined.fits")
    let degree = PreprocessSettings().backgroundDegree
    #expect(
      siril.calls.map(\.script) == [
        SirilScripts.combine(.mono(filter: "L", master: "trim_L"), backgroundDegree: degree)
          .render()
      ])
  }
}
