import Foundation
import StackKit
import TestSupport
import Testing

@Suite("OracleCase loads a recorded legacy run (card 0044)")
struct OracleFixtureTests {
  struct Expected: Sendable, CustomTestStringConvertible {
    let name: String
    let filters: [String]
    let frames: Int
    let anchorNight: String?
    /// The second night's measured rotation, when the case has one (degrees, ±3 like the golden).
    let rotationDeg: Double?
    var testDescription: String { name }
  }

  static let committed: [Expected] = [
    Expected(
      name: "golden-single-night", filters: ["L", "R", "G", "B"], frames: 21, anchorNight: nil,
      rotationDeg: nil),
    Expected(
      name: "golden-two-night", filters: ["L", "R", "G", "B"], frames: 31,
      anchorNight: "2024-03-01", rotationDeg: 35),
  ]

  static func committedCase(_ name: String) throws -> OracleCase {
    let url = try #require(
      Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/oracle"))
    return try OracleCase.load(at: url)
  }

  @Test("every recorded file decodes and agrees with run.json", arguments: committed)
  func testCommittedCasesDecode(_ expected: Expected) throws {
    let oracle = try Self.committedCase(expected.name)
    #expect(try oracle.run().channels.map(\.filter) == expected.filters)
    #expect(try oracle.inventory().frames.count == expected.frames)
    #expect(try oracle.registration().anchorNight == expected.anchorNight)
    try Self.expectConsistent(oracle)
  }

  /// The cross-file invariants every recorded case holds, committed or live.
  static func expectConsistent(
    _ oracle: OracleCase, sourceLocation: SourceLocation = #_sourceLocation
  ) throws {
    let run = try oracle.run()
    let selection = try oracle.selection()
    let grades = try oracle.grades()
    let filters = run.channels.map(\.filter)
    #expect(!filters.isEmpty, sourceLocation: sourceLocation)
    #expect(
      try oracle.calibration().channels.map(\.filter) == filters, sourceLocation: sourceLocation)
    #expect(
      try oracle.registration().channels.map(\.filter) == filters, sourceLocation: sourceLocation)
    #expect(selection.channels.map(\.filter) == filters, sourceLocation: sourceLocation)
    #expect(grades.map(\.filter) == filters, sourceLocation: sourceLocation)
    #expect(try !oracle.steps().isEmpty, sourceLocation: sourceLocation)
    for (picked, channel) in zip(selection.channels, run.channels) {
      #expect(picked.stackedFrames == channel.stackedFrames, sourceLocation: sourceLocation)
      #expect(picked.inputFrames == channel.inputFrames, sourceLocation: sourceLocation)
    }
    for (picked, graded) in zip(selection.channels, grades) {
      #expect(
        picked.kept.count + picked.rejected.count == graded.metrics.count,
        sourceLocation: sourceLocation)
    }
  }

  @Test("scripts are non-empty, numbered 1…n in emission order", arguments: committed)
  func testOracleCase_scripts_ordered(_ expected: Expected) throws {
    let scripts = try Self.committedCase(expected.name).scripts()
    #expect(!scripts.isEmpty)
    #expect(scripts.map(\.number) == Array(1...scripts.count))
    for script in scripts {
      #expect(script.text.hasPrefix("requires "), "\(script.name)")
    }
  }

  @Test("master and layer hashes are sha256 lines over normalized paths", arguments: committed)
  func testOracleCase_hashes_parse(_ expected: Expected) throws {
    let oracle = try Self.committedCase(expected.name)
    let masters = try oracle.masterHashes()
    #expect(masters.count >= expected.filters.count)
    for hash in try masters + oracle.layerHashes() {
      #expect(hash.sha256.count == 64 && hash.sha256.allSatisfy(\.isHexDigit))
      #expect(hash.path.hasPrefix("<ROOT>/"))
    }
  }

  @Test("the second night's rotation is recorded", arguments: committed)
  func testOracleCase_registration_rotation(_ expected: Expected) throws {
    guard let rotation = expected.rotationDeg else { return }
    let registration = try Self.committedCase(expected.name).registration()
    let groups = try #require(registration.channels.first { $0.filter == "L" }?.groups)
    let measured = try #require(groups.compactMap(\.rotationDeg).max())
    #expect(abs(measured - rotation) <= 3)
  }

  @Test("without ~/Documents/astro/fixtures the live lookup finds nothing", .scratchDirectory)
  func testLiveCaseSkipsWhenAbsent() throws {
    #expect(try OracleLiveCases.find("m31-db", home: ScratchDirectory.url) == nil)
  }
}
