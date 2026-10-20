import Foundation
import ImageKit
import StackKit
import TestSupport
import Testing

/// The real multi-night capture of 0044 case (d): M31 broadband + dual-band, one OSC channel over
/// four nights, through the host Siril. Pinned as recorded where the port computes what Go did —
/// calibration masters by hash; photometry, night geometry and the seam records against
/// `run.json` — and the master within a stated bound: its seam pass and saturation repair are float
/// ports (mean |Δ| ≤ 1e-3 of the recorded dynamic range).
@Suite(
  "Live preprocess — M31 BB + DB over four nights", .liveFixtures, .tags(.live),
  .enabled(if: (try? SirilTool.locate()) != nil, "siril-cli absent"),
  .enabled(
    if: BuildConfiguration.optimized,
    "120 frames of 26 MP need an optimized build: just test-heavy"),
  .serialized, .timeLimit(.minutes(30)))
struct PreprocessM31LiveTests {
  static let runID = PreprocessLiveTests.runID

  @Test(
    "calibration masters hash as recorded; records as recorded; the master within the bound",
    .scratchDirectory)
  func testM31MixedLanesLive() async throws {
    let oracle = try LiveInventoryOracleTests.liveCase("m31-bb-db")
    let roots = ["M31-DB", "M31-BB"].flatMap { capture in
      ["lights", "darks", "flats", "bias"].map {
        LiveInventoryOracleTests.captures.appendingPathComponent(capture).appendingPathComponent($0)
      }
    }
    guard roots.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
      try Test.cancel("captures M31-DB/M31-BB absent under ~/Documents/astro/captures")
    }
    let zone = try TimeZone(identifier: oracle.manifest.timezone).unwrapped("timezone")
    let inventory = try InventoryBuilder(timeZone: zone).scan(paths: roots.map(\.path))
    let root = try ScratchDirectory.url
    let request = PreprocessRequest(
      inventory: inventory, output: root.appendingPathComponent("out/M_31/\(Self.runID)"),
      work: root.appendingPathComponent("work/run_\(Self.runID)"), runID: Self.runID)
    let tools = Preprocessor.Tools(runner: .live(binary: try SirilTool.locate()))
    let result = try await Preprocessor(tools: tools).perform(request) { _ in }

    #expect(result.channels.allSatisfy { $0.error == nil })
    let recordedRun = try oracle.run()
    let defects = (recordedRun.warnings ?? []).filter { $0.hasPrefix("dark defect map") }
    #expect(result.warnings.filter { $0.hasPrefix("dark defect map") } == defects)
    // Real frames: the stacked count and the rejected frames move with Siril's star matching.
    let recordedChannel = try #require(recordedRun.channels.first)
    #expect(abs((result.channels.first?.stackedFrames ?? 0) - recordedChannel.stackedFrames) <= 2)
    try PreprocessTwoNightLiveTests.checkRecords(result, oracle: oracle, tolerance: .realData)
    let recordedOut = oracle.directory.deletingLastPathComponent().appendingPathComponent("out")
    let master = try #require(
      FileManager.default.enumerator(at: recordedOut, includingPropertiesForKeys: nil)?.compactMap {
        $0 as? URL
      }
      .first { $0.lastPathComponent == "master_RGB.fits" })
    let mean = try PreprocessTwoNightLiveTests.meanDifference(
      root.appendingPathComponent("out/M_31/\(Self.runID)/master_RGB.fits"), master)
    #expect(mean <= 1e-3, "master_RGB: mean |Δ| \(mean) of the range")
  }
}
