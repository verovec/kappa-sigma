import Foundation
import ImageKit
import ProcessKit
import TestSupport
import Testing

/// The history manifest's bytes (card 0156): a history without versions writes exactly what it
/// wrote before versions existed, so no project's `<history>.json` changes by being reopened.
extension HistoryTests {
  /// The fixture recorded before card 0156 (`RECORD=1` rewrites it from the code under test).
  static let manifestFixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/history/manifest-before-0156.json")

  /// Applies a, b, c; undoes c; snapshots "v1": steps, undone and snapshots all written.
  static func recordedHistory(in directory: URL) throws -> History {
    let history = try History(directory: directory, original: try Self.image([0, 1, 2, 3]))
    try history.apply(processID: "a", params: Self.params, result: try Self.image([1, 1, 1, 1]))
    try history.apply(processID: "b", params: Self.params, result: try Self.image([2, 2, 2, 2]))
    try history.apply(processID: "c", params: Self.params, result: try Self.image([3, 3, 3, 3]))
    try history.undo()
    try history.snapshot(name: "v1")
    return history
  }

  @Test("testManifest_NoVersions_ByteIdentical", .scratchDirectory)
  func testManifest_NoVersions_ByteIdentical() throws {
    let directory = try ScratchDirectory.url.appendingPathComponent("history")
    let history = try Self.recordedHistory(in: directory)
    let written = try Data(
      contentsOf: directory.deletingLastPathComponent().appendingPathComponent("history.json"))
    if ProcessInfo.processInfo.environment["RECORD"] == "1" {
      try FileManager.default.createDirectory(
        at: Self.manifestFixture.deletingLastPathComponent(), withIntermediateDirectories: true)
      try written.write(to: Self.manifestFixture)
    }
    #expect(history.versions.isEmpty)
    #expect(written == (try Data(contentsOf: Self.manifestFixture)))
    #expect(!(String(bytes: written, encoding: .utf8) ?? "").contains("versions"))
  }
}
