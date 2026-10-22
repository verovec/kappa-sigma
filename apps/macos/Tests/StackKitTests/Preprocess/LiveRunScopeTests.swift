import CryptoKit
import Foundation
import ImageKit
import StackKit
import TestSupport
import Testing

/// Card 0095 on real captures: M 31 (M31-DB) and IC 1848 imported into one project are two
/// scopes; each scoped run writes the same masters as a run of that capture alone — same scripts
/// and selection, so the same bytes (Siril does the pixel math).
@Suite(
  "Live run scope — M 31 + IC 1848 in one scan stack as two runs, byte-identical to one each",
  .liveFixtures, .tags(.live),
  .enabled(if: (try? SirilTool.locate()) != nil, "siril-cli absent"),
  .enabled(
    if: BuildConfiguration.optimized,
    "four runs of 26 MP captures need an optimized build: just test-heavy"),
  .serialized, .timeLimit(.minutes(60)))
struct LiveRunScopeTests {
  static let captures = ["M31-DB", "IC1848"]

  /// The capture folders of `names` (lights, darks, flats, bias), or a cancelled test.
  static func roots(_ names: [String]) throws -> [URL] {
    let roots = names.flatMap { capture in
      ["lights", "darks", "flats", "bias"].map {
        LiveInventoryOracleTests.captures.appendingPathComponent(capture).appendingPathComponent($0)
      }
    }
    guard roots.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
      try Test.cancel(
        "captures \(names.joined(separator: "/")) absent under ~/Documents/astro/captures")
    }
    return roots
  }

  /// SHA-256 of each channel master's data unit, by filter.
  static func masterHashes(_ result: PreprocessResult) throws -> [String: String] {
    var hashes: [String: String] = [:]
    for channel in result.channels {
      guard let path = channel.masterPath else { continue }
      let body = try FITSFile.read(at: URL(fileURLWithPath: path)).dataUnit
      hashes[channel.filter] = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
    }
    return hashes
  }

  static func run(_ inventory: Inventory, name: String, root: URL) async throws -> PreprocessResult
  {
    let request = PreprocessRequest(
      inventory: inventory, output: root.appendingPathComponent("out/\(name)"),
      work: root.appendingPathComponent("work/run_\(name)"), runID: name)
    let tools = Preprocessor.Tools(
      runner: .make(mode: .pipe, binary: try SirilTool.locate(), work: request.work))
    return try await Preprocessor(tools: tools).perform(request) { _ in }
  }

  @Test(
    "two objects → two scopes → two stacks whose masters equal the single-capture runs'",
    .scratchDirectory)
  func testTwoObjectsTwoStacks() async throws {
    let zone = try TimeZone(identifier: "Europe/Paris").unwrapped("timezone")
    let builder = InventoryBuilder(timeZone: zone)
    let both = try builder.scan(paths: try Self.roots(Self.captures).map(\.path))
    let scopes = RunScope.scopes(of: both)
    #expect(scopes.count == 2, "\(scopes.map(\.object))")
    #expect(throws: PreprocessError.self) { try Preprocessor.plan(both) }

    let root = try ScratchDirectory.url
    for (scope, capture) in zip(scopes, Self.captures.sorted()) {
      let scoped = try await Self.run(both.scoped(scope), name: "scoped_\(capture)", root: root)
      let alone = try await Self.run(
        try builder.scan(paths: try Self.roots([capture]).map(\.path)), name: "alone_\(capture)",
        root: root)
      let (scopedHashes, aloneHashes) = (
        try Self.masterHashes(scoped), try Self.masterHashes(alone)
      )
      #expect(!scopedHashes.isEmpty)
      #expect(
        scopedHashes == aloneHashes, "\(scope.object): the scoped run equals the capture alone")
    }
  }
}
