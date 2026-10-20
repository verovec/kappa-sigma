import Foundation
import ImageKit
import StackKit
import TestSupport
import Testing

/// The real two-night pipeline on 0044 case (b)'s frames with the host Siril.
///
/// Siril-only outputs (the calibration masters, G and B) hash as recorded. Everything the port
/// computes that the legacy duplicate-frame bug did not touch is pinned against `run.json` /
/// `registration.json`: photometry, geometry, seam offsets, the seam noise weights. L and R
/// legitimately differ from the recording — they stack their 5 real frames, not 10 (PO
/// 2026-10-20) — so they are held to a stated bound instead: mean |Δ| ≤ 1e-3 of the recorded
/// dynamic range (measured 3.1e-4 before the seam pass was ported).
@Suite(
  "Live preprocess — the synthetic two nights", .liveFixtures, .tags(.live),
  .enabled(if: (try? SirilTool.locate()) != nil, "siril-cli absent"), .serialized,
  .timeLimit(.minutes(5)))
struct PreprocessTwoNightLiveTests {
  static let runID = PreprocessLiveTests.runID
  typealias Object = [String: Any]

  static func run(_ oracle: OracleCase, root: URL) async throws -> PreprocessResult {
    let input = oracle.directory.deletingLastPathComponent().appendingPathComponent("in")
    let zone = try TimeZone(identifier: oracle.manifest.timezone).unwrapped("timezone")
    let inventory = try InventoryBuilder(timeZone: zone).scan(paths: [input.path])
    let request = PreprocessRequest(
      inventory: inventory, output: root.appendingPathComponent("out/TESTFIELD/\(runID)"),
      work: root.appendingPathComponent("work/run_\(runID)"), runID: runID)
    let tools = Preprocessor.Tools(runner: .live(binary: try SirilTool.locate()))
    return try await Preprocessor(tools: tools).perform(request) { _ in }
  }

  /// Mean |Δ| over the recorded image's dynamic range (P99.9 − P0.1; its sky is near zero).
  static func meanDifference(_ ours: URL, _ recorded: URL) throws -> Double {
    let (x, y) = (try FITSFile.read(at: ours).image().planes[0], try FITSFile.read(at: recorded).image().planes[0])
    guard x.count == y.count else { return .infinity }
    let sorted = y.map(Double.init).sorted()
    let range = sorted[Int(0.999 * Double(sorted.count - 1))] - sorted[Int(0.001 * Double(sorted.count - 1))]
    return zip(x, y).map { abs(Double($0) - Double($1)) }.reduce(0, +) / Double(x.count) / max(range, 1e-12)
  }

  static func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= 1e-9 * max(abs(b), 1e-12) }

  @Test("Siril-only masters hash as recorded; L and R within the stated bound", .scratchDirectory)
  func testTwoNightMastersByteIdentical() async throws {
    let home = FileManager.default.homeDirectoryForCurrentUser
    guard let oracle = try OracleLiveCases.find("golden-two-night", home: home) else {
      try Test.cancel("case (b) is not recorded under ~/Documents/astro/fixtures")
    }
    let root = try ScratchDirectory.url
    let result = try await Self.run(oracle, root: root)
    #expect(result.channels.allSatisfy { $0.error == nil })
    let sirilOnly = try oracle.masterHashes().filter {
      !$0.path.hasSuffix("master_L.fits") && !$0.path.hasSuffix("master_R.fits")
    }
    #expect(try PreprocessLiveTests.hashes(of: sirilOnly, root: root) == sirilOnly.map { "\($0.sha256)  \($0.path)" })
    let recordedOut = oracle.directory.deletingLastPathComponent().appendingPathComponent("out/TESTFIELD")
    let recordedRun = try #require(try FileManager.default.contentsOfDirectory(at: recordedOut, includingPropertiesForKeys: nil).first)
    for channel in ["L", "R"] {
      let mean = try Self.meanDifference(
        root.appendingPathComponent("out/TESTFIELD/\(Self.runID)/master_\(channel).fits"),
        recordedRun.appendingPathComponent("master_\(channel).fits"))
      #expect(mean <= 1e-3, "\(channel): mean |Δ| \(mean) of the range")
    }
    try Self.checkRecords(result, oracle: oracle)
  }

  /// Photometry, geometry and the seam records against the recording.
  static func checkRecords(_ result: PreprocessResult, oracle: OracleCase) throws {
    let run = try JSONSerialization.jsonObject(with: Data(contentsOf: oracle.directory.appendingPathComponent("run.json"))) as? Object
    let channels = try #require(run?["channels"] as? [Object])
    for (ours, recorded) in zip(result.channels, channels) {
      let groups = recorded["groups"] as? [Object] ?? []
      let photometry = groups.compactMap { $0["photom"] as? Object }
      #expect(ours.photometry.count == photometry.count, "\(ours.filter) photometry")
      for (record, theirs) in zip(ours.photometry, photometry) {
        #expect(close(record.scale, theirs["scale"] as? Double ?? 0) && close(record.offset, theirs["offset"] as? Double ?? 0))
        #expect(close(record.residual, theirs["resid"] as? Double ?? 0) && record.applied == (theirs["applied"] as? Bool ?? false))
      }
      if ours.nights.count > 1 {
        for (night, theirs) in zip(ours.nights, groups) {
          #expect(close(night.rotationDegrees ?? .nan, theirs["rotation_deg"] as? Double ?? 0))
          #expect(close(night.overlapFraction ?? .nan, theirs["overlap_frac"] as? Double ?? 0))
        }
      }
      let seam = recorded["seam"] as? Object
      let offsets = seam?["offsets"] as? [Object] ?? []
      #expect(ours.seamOffsets.map(\.reason) == offsets.map { $0["reason"] as? String ?? "" })
      let noise = try #require(seam?["noise_eq"] as? Object)
      let record = try #require(ours.seamNoise)
      #expect(record.applied == (noise["applied"] as? Bool ?? false) && record.depthMin == noise["depth_min"] as? Int)
      #expect(record.depthMax == noise["depth_max"] as? Int && record.weightMax == noise["weight_max"] as? Double)
      #expect(record.reason == noise["reason"] as? String ?? "")
    }
  }
}
