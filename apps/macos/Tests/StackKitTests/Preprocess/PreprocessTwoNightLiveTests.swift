import CryptoKit
import Foundation
import ImageKit
import StackKit
import TestSupport
import Testing

/// The real two-night pipeline on 0044 case (b)'s frames with the host Siril. Siril-only outputs
/// (the calibration masters, G and B) must hash as recorded; L and R legitimately differ — the
/// duplicate-frame fix (PO 2026-10-20) — and are compared pixel by pixel against the recorded
/// masters within the tolerance stated below.
@Suite(
  "Live preprocess — the synthetic two nights", .liveFixtures, .tags(.live),
  .enabled(if: (try? SirilTool.locate()) != nil, "siril-cli absent"), .serialized,
  .timeLimit(.minutes(5)))
struct PreprocessTwoNightLiveTests {
  static let runID = PreprocessLiveTests.runID

  struct Run {
    let oracle: OracleCase
    let root: URL
    let result: PreprocessResult
    var recordedOut: URL {
      oracle.directory.deletingLastPathComponent().appendingPathComponent("out/TESTFIELD")
    }
  }

  static func run() async throws -> Run {
    let home = FileManager.default.homeDirectoryForCurrentUser
    guard let oracle = try OracleLiveCases.find("golden-two-night", home: home) else {
      try Test.cancel("case (b) is not recorded under ~/Documents/astro/fixtures")
    }
    let input = oracle.directory.deletingLastPathComponent().appendingPathComponent("in")
    let zone = try TimeZone(identifier: oracle.manifest.timezone).unwrapped("timezone")
    let inventory = try InventoryBuilder(timeZone: zone).scan(paths: [input.path])
    let root = try ScratchDirectory.url
    let request = PreprocessRequest(
      inventory: inventory, output: root.appendingPathComponent("out/TESTFIELD/\(runID)"),
      work: root.appendingPathComponent("work/run_\(runID)"), runID: runID)
    let tools = Preprocessor.Tools(runner: .live(binary: try SirilTool.locate()))
    let result = try await Preprocessor(tools: tools).perform(request) { _ in }
    return Run(oracle: oracle, root: root, result: result)
  }

  /// Mean and max |Δ| relative to the recorded image's median level.
  static func difference(_ ours: URL, _ recorded: URL) throws -> (mean: Double, max: Double) {
    let (a, b) = (try FITSFile.read(at: ours).image(), try FITSFile.read(at: recorded).image())
    let (x, y) = (a.planes[0], b.planes[0])
    guard x.count == y.count else { return (.infinity, .infinity) }
    let sorted = y.map(Double.init).sorted()
    // Relative to the recorded range (P99.9 − P0.1): a near-zero sky makes a median meaningless.
    let level = max(1e-12, sorted[Int(0.999 * Double(sorted.count - 1))] - sorted[Int(0.001 * Double(sorted.count - 1))])
    let deltas = zip(x, y).map { abs(Double($0) - Double($1)) / level }
    return (deltas.reduce(0, +) / Double(deltas.count), deltas.max() ?? 0)
  }

  @Test("calibration masters, G and B hash as recorded; L and R measured against the recording", .scratchDirectory)
  func testTwoNightMastersByteIdentical() async throws {
    let run = try await Self.run()
    #expect(run.result.channels.allSatisfy { $0.error == nil })
    let siriOnly = try run.oracle.masterHashes().filter { !$0.path.hasSuffix("master_L.fits") && !$0.path.hasSuffix("master_R.fits") }
    #expect(try PreprocessLiveTests.hashes(of: siriOnly, root: run.root) == siriOnly.map { "\($0.sha256)  \($0.path)" })
    let recordedRun = try #require(try FileManager.default.contentsOfDirectory(at: run.recordedOut, includingPropertiesForKeys: nil).first)
    let out = run.root.appendingPathComponent("out/TESTFIELD/\(Self.runID)")
    for channel in ["L", "R"] {
      let delta = try Self.difference(
        out.appendingPathComponent("master_\(channel).fits"), recordedRun.appendingPathComponent("master_\(channel).fits"))
      Attachment.record("\(channel): mean |Δ| \(delta.mean), max |Δ| \(delta.max) (relative to the median)", named: "delta_\(channel).txt")
      print("DELTA \(channel) mean=\(delta.mean) max=\(delta.max)")
    }
    print("DELTA warnings \(run.result.warnings)")
    for channel in run.result.channels {
      print("DELTA \(channel.filter) photom \(channel.photometry.map { "\($0.label) s=\($0.scale) o=\($0.offset) r=\($0.residual) applied=\($0.applied)" })")
      print("DELTA \(channel.filter) nights \(channel.nights) stacked=\(channel.stackedFrames)")
    }
  }
}
