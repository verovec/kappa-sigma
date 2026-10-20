import Foundation
import ImageKit
import StackKit
import TestSupport
import Testing
import CryptoKit

/// The real pipeline on 0044 case (a)'s frames with the host Siril: Siril does the pixel math, so
/// the same scripts and the same selection must give byte-identical masters, aligned channels and
/// trims (the data unit: Siril stamps DATE in every header).
@Suite(
  "Live preprocess — the synthetic single night, byte for byte", .liveFixtures, .tags(.live),
  .enabled(if: (try? SirilTool.locate()) != nil, "siril-cli absent"), .serialized,
  .timeLimit(.minutes(5)))
struct PreprocessLiveTests {
  static let runID = "RUNID48"

  /// `<sha256 of the data unit>  <path normalized to <ROOT>/<RUN>>` for each recorded path.
  static func hashes(of recorded: [OracleHash], root: URL) throws -> [String] {
    try recorded.map { entry in
      let path = entry.path.replacingOccurrences(of: "<ROOT>", with: root.path)
        .replacingOccurrences(of: "<RUN>", with: runID)
      let body = try FITSFile.read(at: URL(fileURLWithPath: path)).dataUnit
      let digest = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
      return "\(digest)  \(entry.path)"
    }
  }

  @Test(
    "masters, aligned channels and trims hash as recorded, in script and pipe mode",
    .scratchDirectory, arguments: [SirilMode.script, .pipe])
  func testSingleNightMastersByteIdentical(mode: SirilMode) async throws {
    let home = FileManager.default.homeDirectoryForCurrentUser
    guard let oracle = try OracleLiveCases.find("golden-single-night", home: home) else {
      try Test.cancel("case (a) is not recorded under ~/Documents/astro/fixtures")
    }
    let input = oracle.directory.deletingLastPathComponent().appendingPathComponent("in")
    let zone = try TimeZone(identifier: oracle.manifest.timezone).unwrapped("timezone")
    let inventory = try InventoryBuilder(timeZone: zone).scan(paths: [input.path])
    let root = try ScratchDirectory.url
    let request = PreprocessRequest(
      inventory: inventory, output: root.appendingPathComponent("out/TESTFIELD/\(Self.runID)"),
      work: root.appendingPathComponent("work/run_\(Self.runID)"), runID: Self.runID)
    let tools = Preprocessor.Tools(
      runner: .make(mode: mode, binary: try SirilTool.locate(), work: request.work))
    let result = try await Preprocessor(tools: tools).perform(request) { _ in }

    #expect(result.channels.allSatisfy { $0.error == nil })
    let masters = try oracle.masterHashes()
    #expect(try Self.hashes(of: masters, root: root) == masters.map { "\($0.sha256)  \($0.path)" })
    let layers = try oracle.layerHashes()
    #expect(try Self.hashes(of: layers, root: root) == layers.map { "\($0.sha256)  \($0.path)" })
    #expect(
      result.bundle?.layers.map(\.file) == [
        "trim_L.fits", "trim_R.fits", "trim_G.fits", "trim_B.fits",
      ])
  }
}
