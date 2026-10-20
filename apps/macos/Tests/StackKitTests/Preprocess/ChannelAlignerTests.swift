import Foundation
import StackKit
import TestSupport
import Testing

/// `ParityNormalizer` + `ChannelAligner` are `normalizeMasterParity` and `alignChannels`
/// (`parity.go`, `alignchannels.go`): parity before registration, a pair rescue, and a policy
/// that never degrades silently.
@Suite("ChannelAligner — parity, co-registration, rescue, policy")
struct ChannelAlignerTests {
  /// Masters `master_<F>.fits` in a scratch `out`; returns filter → path and the folders.
  static func masters(_ filters: [String]) throws -> (masters: [String: String], out: URL, work: URL) {
    let out = try ScratchDirectory.url.appendingPathComponent("out")
    var masters: [String: String] = [:]
    for filter in filters {
      let url = out.appendingPathComponent("master_\(filter).fits")
      try PipelineSiril.frame(url)
      masters[filter] = url.path
    }
    return (masters, out, try ScratchDirectory.url.appendingPathComponent("work"))
  }

  static func align(_ siril: PipelineSiril, _ filters: [String]) async throws -> ([String: String], [String]) {
    let (masters, out, work) = try Self.masters(filters)
    var journal = PreprocessJournal()
    let aligned = try await ChannelAligner(runner: siril.runner).align(
      masters, folder: work.appendingPathComponent("04_aligned"), out: out, journal: &journal)
    return (aligned, journal.warnings)
  }

  @Test("channels in the canonical order, custom names after, sorted")
  func testOrdered() {
    #expect(ChannelAligner.ordered(["Zed", "B", "Ha", "L", "Abc", "R"]) == ["L", "R", "B", "Ha", "Abc", "Zed"])
  }

  @Test("an opposite-parity master is mirrored; nothing solved is a skipped check", .scratchDirectory)
  func testParity() async throws {
    let siril = PipelineSiril(solve: { $0 == "master_G" ? 1 : -1 })
    let (aligned, warnings) = try await Self.align(siril, ["L", "R", "G", "B"])
    #expect(aligned == ["L": "aligned_L", "R": "aligned_R", "G": "aligned_G", "B": "aligned_B"])
    #expect(warnings == ["channel G: master mirror-corrected (opposite parity vs L) before channel alignment"])
    #expect(siril.calls.contains { $0.script.hasSuffix("load master_G\nmirrorx\nsave master_G\n") })
    #expect(siril.calls.filter { $0.script.contains("platesolve -noflip") }.count == 4)

    let (_, unsolved) = try await Self.align(PipelineSiril(), ["L", "R"])
    #expect(unsolved == ["channel parity check skipped (no master could be plate-solved)"])
  }

  @Test("a channel the joint registration misses is rescued by a pair registration", .scratchDirectory)
  func testPairRescue() async throws {
    let siril = PipelineSiril(missing: ["r_ch_00004.fits"])
    let (aligned, _) = try await Self.align(siril, ["L", "R", "G", "B"])
    #expect(aligned["B"] == "aligned_B")
    let pair = try #require(siril.calls.last)
    #expect(pair.directory.lastPathComponent == "pair_B" && pair.script.contains("setref pair 1"))
  }

  @Test(
    "what a channel that still fails costs: R/G/B all, L itself, an accent channel itself",
    .scratchDirectory,
    arguments: [
      ("B", ["L", "R", "G", "B"], "channel B could not be co-registered — combining unaligned channels"),
      ("L", ["L", "R", "G", "B"], "L could not be co-registered — combining without luminance"),
      ("Ha", ["R", "G", "B", "Ha"], "Ha could not be co-registered — omitted from the composite"),
    ])
  func testPolicy(failing: String, filters: [String], warning: String) async throws {
    let index = try #require(ChannelAligner.ordered(filters).firstIndex(of: failing)) + 1
    let siril = PipelineSiril(missing: [String(format: "r_ch_%05d.fits", index), "r_pair_00002.fits"])
    let (aligned, warnings) = try await Self.align(siril, filters)
    #expect(warnings.last == warning)
    if failing == "B" {
      #expect(aligned == ["L": "master_L", "R": "master_R", "G": "master_G", "B": "master_B"])
    } else {
      #expect(aligned[failing] == nil && aligned.count == 3)
    }
  }

  @Test("mixed master sizes and a failed registration combine the masters unaligned", .scratchDirectory)
  func testUnaligned() async throws {
    let (masters, out, work) = try Self.masters(["R", "G"])
    try TestFITS.write("master_B.fits", in: out, width: 4, height: 4, cards: [:])
    var all = masters
    all["B"] = out.appendingPathComponent("master_B.fits").path
    var journal = PreprocessJournal()
    let siril = PipelineSiril()
    let aligned = try await ChannelAligner(runner: siril.runner).align(
      all, folder: work.appendingPathComponent("04_aligned"), out: out, journal: &journal)
    #expect(aligned == ["R": "master_R", "G": "master_G", "B": "master_B"])
    #expect(journal.warnings.first?.hasPrefix("channel masters have mixed dimensions (R 256×256, G 256×256, B 4×4)") == true)
    #expect(siril.calls.isEmpty)

    let failing = SirilRunner { script, _, _ in
      if script.render().contains("seqapplyreg") { throw SirilError.scriptFailed(exitCode: 1, hint: "x") }
      return ""
    }
    var second = PreprocessJournal()
    let fallback = try await ChannelAligner(runner: failing).align(
      masters, folder: work.appendingPathComponent("04_b"), out: out, journal: &second)
    #expect(fallback == ["R": "master_R", "G": "master_G"])
    #expect(second.warnings.last?.hasPrefix("cross-channel alignment failed, using unaligned channels") == true)
  }

  @Test("one channel is passed through, nothing run", .scratchDirectory)
  func testSingleChannel() async throws {
    let siril = PipelineSiril()
    let (aligned, warnings) = try await Self.align(siril, ["RGB"])
    #expect(aligned == ["RGB": "master_RGB"] && warnings.isEmpty && siril.calls.isEmpty)
  }
}
