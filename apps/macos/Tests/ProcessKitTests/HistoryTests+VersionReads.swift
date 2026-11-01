import Foundation
import ImageKit
import ProcessKit
import TestSupport
import Testing

/// Card 0159: what the Versions menu reads of a version — the image it ended on, a step's mask,
/// the bytes only it keeps — and the errors on an unknown version or step.
extension HistoryTests {
  @Test(
    "a version's head, its undone steps left out; its own bytes; unknown ids refused",
    .scratchDirectory)
  func testVersionReads() async throws {
    let directory = try ScratchDirectory.url.appendingPathComponent("history")
    let history = try Self.threeSteps(in: directory)
    try history.undo()
    try await history.revise(from: 1, label: "v") { revised in
      try revised.apply(processID: "x", params: Self.params, result: try Self.image([9, 9, 9, 9]))
    }
    let version = try #require(history.versions.last)
    #expect(version.redo == 1)

    #expect(try history.head(ofVersion: version.id).planes == [[2, 2, 2, 2]], "b, c undone")
    #expect(try history.mask(ofVersion: version.id, step: 0) == nil)
    #expect(try history.bytes(ofVersion: version.id) > 0)
    #expect(throws: HistoryError.noStep(5)) { try history.mask(ofVersion: version.id, step: 5) }
    #expect(throws: HistoryError.unknownVersion("nope")) { try history.head(ofVersion: "nope") }
    #expect(throws: HistoryError.unknownVersion("nope")) { try history.bytes(ofVersion: "nope") }
  }
}
