import Foundation
import StackKit
import TestSupport
import Testing

@Suite("OracleCase refuses a recording that does not match its manifest")
struct OracleCaseIntegrityTests {
  /// A hand-written minimal case: one file and a manifest holding its sha256.
  static func writeMinimalCase(at url: URL, body: String = "1/1 step\n") throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try Data(body.utf8).write(to: url.appendingPathComponent("steps.txt"))
    // sha256("1/1 step\n")
    let manifest = """
      {"case": "minimal", "title": "hand-written", "siril": "siril 1.4.4", "timezone": "UTC",
       "legacy_commit": "0", "files": {"steps.txt":
       "eec56ed907112df2368e4b71152dbf681ae923dead3e8c184e65a7c4d4ce49f1"}}
      """
    try Data(manifest.utf8).write(to: url.appendingPathComponent("manifest.json"))
  }

  @Test("a minimal case loads and exposes its manifest and steps", .scratchDirectory)
  func testOracleCase_load_minimal() throws {
    let url = try ScratchDirectory.url.appendingPathComponent("minimal")
    try Self.writeMinimalCase(at: url)
    let oracle = try OracleCase.load(at: url)
    #expect(oracle.manifest.caseName == "minimal")
    #expect(oracle.manifest.siril == "siril 1.4.4")
    #expect(try oracle.steps() == ["1/1 step"])
  }

  @Test("a file edited after recording fails its hash", .scratchDirectory)
  func testOracleCase_load_rejectsEditedFile() throws {
    let url = try ScratchDirectory.url.appendingPathComponent("minimal")
    try Self.writeMinimalCase(at: url)
    try Data("2/2 other\n".utf8).write(to: url.appendingPathComponent("steps.txt"))
    #expect(throws: OracleCaseError.hashMismatch(file: "steps.txt")) {
      try OracleCase.load(at: url)
    }
  }

  @Test("a file listed in the manifest but missing fails", .scratchDirectory)
  func testOracleCase_load_rejectsMissingFile() throws {
    let url = try ScratchDirectory.url.appendingPathComponent("minimal")
    try Self.writeMinimalCase(at: url)
    try FileManager.default.removeItem(at: url.appendingPathComponent("steps.txt"))
    #expect(throws: OracleCaseError.missingFile("steps.txt")) { try OracleCase.load(at: url) }
  }

  @Test(
    "a listed file that exists but cannot be read is not reported as missing", .scratchDirectory)
  func testOracleCase_load_unreadableIsNotMissing() throws {
    let url = try ScratchDirectory.url.appendingPathComponent("minimal")
    try Self.writeMinimalCase(at: url)
    let steps = url.appendingPathComponent("steps.txt").path
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: steps)
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: steps)
    }

    let error = #expect(throws: (any Error).self) { try OracleCase.load(at: url) }
    #expect(error as? OracleCaseError == nil, "a permission error must surface as itself")
  }

  @Test("scripts() lists only NNNN_<dir>.ssf files, in number order", .scratchDirectory)
  func testOracleCase_scripts_ignoresOtherEntries() throws {
    let url = try ScratchDirectory.url.appendingPathComponent("minimal")
    try Self.writeMinimalCase(at: url)
    let scripts = url.appendingPathComponent("scripts", isDirectory: true)
    try FileManager.default.createDirectory(
      at: scripts.appendingPathComponent("nested"), withIntermediateDirectories: true)
    try Data([0xFF, 0xFE, 0x00]).write(to: scripts.appendingPathComponent(".DS_Store"))
    try Data("requires 1.2.0\n".utf8).write(to: scripts.appendingPathComponent("0002_b.ssf"))
    try Data("requires 1.2.0\n".utf8).write(to: scripts.appendingPathComponent("0001_a.ssf"))

    let found = try OracleCase.load(at: url).scripts()
    #expect(found.map(\.name) == ["0001_a.ssf", "0002_b.ssf"])
  }

  @Test("a folder without manifest.json is not a case", .scratchDirectory)
  func testOracleCase_load_rejectsFolderWithoutManifest() throws {
    let url = try ScratchDirectory.url
    #expect(throws: OracleCaseError.missingManifest(path: url.path)) {
      try OracleCase.load(at: url)
    }
  }

  @Test(
    "malformed hash lines are reported with their line number",
    arguments: ["not-a-hash  path", "abc", "\(String(repeating: "g", count: 64))  <ROOT>/x"])
  func testOracleHash_parse_rejectsMalformedLines(_ line: String) {
    #expect(throws: OracleCaseError.malformedHashLine(file: "masters.sha256", line: 1)) {
      try OracleHash.parse("\(line)\n", file: "masters.sha256")
    }
  }
}
