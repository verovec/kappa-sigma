import Foundation
import ImageKit
import ProcessKit
import TestSupport
import Testing

/// Masks recorded on steps (card 0160): a step applied under a mask keeps the mask's pixels as a
/// file of its own, so a replay or a re-edit applies it exactly as it was applied (R2).
extension HistoryTests {
  static let mask: [Float] = [1, 0, 0.5, 1]

  @Test("testApply_WithMask_RecordsFile", .scratchDirectory)
  func testApply_WithMask_RecordsFile() throws {
    let directory = try ScratchDirectory.url.appendingPathComponent("history")
    let history = try History(directory: directory, original: try Self.image([0, 1, 2, 3]))

    try history.apply(processID: "a", params: Self.params, result: try Self.image([1, 1, 1, 1]))
    try history.apply(
      processID: "b", params: Self.params, result: try Self.image([2, 2, 2, 2]),
      mask: try Self.image(Self.mask))

    #expect(history.steps[0].mask == nil, "an unmasked step records no mask")
    let file = try #require(history.steps[1].mask)
    #expect(file == "step-0002-mask.fits")
    #expect(try Self.files(in: directory).contains(file))
    #expect(history.referencedFiles.contains(file))
    #expect(try history.mask(ofStep: 1)?.planes == [Self.mask])
    #expect(try history.mask(ofStep: 0) == nil)
    #expect(throws: HistoryError.noStep(2)) { try history.mask(ofStep: 2) }

    // Undone then dropped by a new step: the mask goes with its step on save.
    try history.undo()
    try history.apply(processID: "c", params: Self.params, result: try Self.image([3, 3, 3, 3]))
    try history.save()
    #expect(!(try Self.files(in: directory).contains(file)))
  }

  @Test("testManifest_Unmasked_ByteIdentical", .scratchDirectory)
  func testManifest_Unmasked_ByteIdentical() throws {
    let directory = try ScratchDirectory.url.appendingPathComponent("history")
    _ = try Self.recordedHistory(in: directory)
    let written = try Self.manifestData(directory)
    #expect(written == (try Data(contentsOf: Self.manifestFixture)))
    #expect(!(String(bytes: written, encoding: .utf8) ?? "").contains("\"mask\""))
  }

  @Test("testReopen_RestoresMask", .scratchDirectory)
  func testReopen_RestoresMask() async throws {
    let directory = try ScratchDirectory.url.appendingPathComponent("history")
    let history = try Self.threeSteps(in: directory)
    try await history.revise(from: 1, label: "masked b") { revised in
      try revised.apply(
        processID: "b", params: Self.params, result: try Self.image([5, 5, 5, 5]),
        mask: try Self.image(Self.mask))
    }
    try history.save()

    let reopened = try History.reopen(
      directory: directory, original: try Self.image([0, 1, 2, 3])
    ) { _ in Self.gainSchema }

    #expect(reopened.steps == history.steps)
    #expect(reopened.steps[1].mask == "step-0004-mask.fits")
    #expect(try reopened.mask(ofStep: 1)?.planes == [Self.mask])
    #expect(reopened.versions.flatMap(\.steps).allSatisfy { $0.mask == nil })
    #expect(reopened.referencedFiles.contains("step-0004-mask.fits"))
  }
}
