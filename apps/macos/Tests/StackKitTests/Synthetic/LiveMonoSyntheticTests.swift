import CryptoKit
import Foundation
import ImageKit
import StackKit
import TestSupport
import Testing

/// Card 0142 with the real Siril: each synthetic scenario stacked twice from the same generated
/// frames — a bundle and a combined image every time (L alone included), the masters and the
/// combined image the same bytes both times, the OSC clip lane split into its two lines.
@Suite(
  "Live mono scenarios — synthetic captures stacked by Siril, stable twice", .liveFixtures,
  .tags(.live), .enabled(if: (try? SirilTool.locate()) != nil, "siril-cli absent"), .serialized,
  .timeLimit(.minutes(6)))
struct LiveMonoSyntheticTests {
  /// One run of `scenario` under `root`: the result and the data-unit hash of every master and
  /// of the combined image, by file name.
  static func run(_ scenario: SyntheticCapture.Scenario, root: URL) async throws
    -> (PreprocessResult, [String: String])
  {
    try SyntheticCapture(scenario).write(under: root.appendingPathComponent("in"))
    let inventory = try MonoScenarioTests.scan(scenario, root: root)
    let request = PreprocessRequest(
      inventory: inventory, output: root.appendingPathComponent("out/SYNTH/R1"),
      work: root.appendingPathComponent("work/run_R1"), runID: "R1")
    let tools = Preprocessor.Tools(
      runner: .make(mode: .script, binary: try SirilTool.locate(), work: request.work))
    let result = try await Preprocessor(tools: tools).perform(request) { _ in }
    var hashes: [String: String] = [:]
    let files = try FileManager.default.contentsOfDirectory(atPath: request.output.path)
    for name in files
    where name.hasSuffix(".fits") && (name.hasPrefix("master_") || name == "combined.fits") {
      let body = try FITSFile.read(at: request.output.appendingPathComponent(name)).dataUnit
      hashes[name] = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
    }
    return (result, hashes)
  }

  @Test(
    "testRun: a bundle and combined.fits for every scenario, the same bytes twice",
    .scratchDirectory, arguments: SyntheticCapture.Scenario.allCases)
  func testRun(scenario: SyntheticCapture.Scenario) async throws {
    let root = try ScratchDirectory.url
    let started = ContinuousClock.now
    // Not `a`/`b`: a folder named after a filter (`b` is blue) types an OSC night's frames.
    let (first, hashes) = try await Self.run(scenario, root: root.appendingPathComponent("first"))
    let (_, again) = try await Self.run(scenario, root: root.appendingPathComponent("second"))
    Attachment.record(
      "\(ContinuousClock.now - started)\n\(first.notes)\n\(first.warnings)\n\(hashes)",
      named: "\(scenario.rawValue).txt")
    #expect(first.channels.allSatisfy { $0.error == nil }, "\(first.channels.map(\.error))")
    let bundle = try #require(first.bundle)
    #expect(first.combinedPath?.hasSuffix("/combined.fits") == true)
    #expect(hashes["combined.fits"] != nil)
    let unstable = Set(hashes.keys).union(again.keys).filter { hashes[$0] != again[$0] }.sorted()
    #expect(!hashes.isEmpty && hashes == again, "not stable twice: \(unstable)")
    let ids = Set(bundle.layers.map(\.id))
    switch scenario {
    case .lrgbHa: #expect(ids == ["L", "R", "G", "B", "Ha"])
    case .sho: #expect(ids == ["Ha", "OIII", "SII"])
    case .lOnly: #expect(ids == ["L"])
    // Siril's debayered masters have three planes: the SII + OIII clip splits into its lines.
    case .oscSIIOIII: #expect(ids == ["RGB", "SII", "OIII"], "\(first.notes)")
    }
  }
}
