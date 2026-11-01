import Foundation
import ImageKit
import ProcessKit
import TestSupport
import Testing

/// History versions (card 0156): revising from step k keeps the superseded tail k…n as a
/// version with its files, restore swaps it back without recompute, nothing is lost.
extension HistoryTests {
  struct Failed: Error, Equatable {}

  /// A history with steps a, b, c (outputs 1, 2, 3 everywhere) over the original 0…3.
  static func threeSteps(in directory: URL) throws -> History {
    let history = try History(directory: directory, original: try Self.image([0, 1, 2, 3]))
    for (id, value) in [("a", Float(1)), ("b", 2), ("c", 3)] {
      try history.apply(
        processID: id, params: Self.params,
        result: try Self.image(Array(repeating: value, count: 4)))
    }
    return history
  }

  static func manifestData(_ directory: URL) throws -> Data {
    try Data(
      contentsOf: directory.deletingLastPathComponent().appendingPathComponent("history.json"))
  }

  @Test("testRevise_KeepsTailAsVersion", .scratchDirectory, arguments: [0, 1, 2])
  func testRevise_KeepsTailAsVersion(from index: Int) async throws {
    let directory = try ScratchDirectory.url.appendingPathComponent("history")
    let history = try Self.threeSteps(in: directory)
    let before = history.steps
    let files = try Self.files(in: directory)
    var seen: [[Float]] = []

    try await history.revise(from: index, label: "gain 2") { revised in
      // The body starts on the output of k-1 (the original for k = 0).
      seen = revised.current.planes
      try revised.apply(processID: "x", params: Self.params, result: try Self.image([9, 9, 9, 9]))
    }

    let previous: [Float] = index == 0 ? [0, 1, 2, 3] : Array(repeating: Float(index), count: 4)
    #expect(seen == [previous])
    #expect(history.steps.map(\.processID) == before[..<index].map(\.processID) + ["x"])
    let version = try #require(history.versions.last)
    #expect(version.steps == Array(before[index...]) && version.base == index)
    #expect(version.label == "gain 2" && !history.canRedo)
    #expect(try Self.files(in: directory).isSuperset(of: files), "no file removed")
    #expect(history.referencedFiles.isSuperset(of: before.map(\.file)))
  }

  @Test("testRestore_SwapsTails", .scratchDirectory)
  func testRestore_SwapsTails() async throws {
    let directory = try ScratchDirectory.url.appendingPathComponent("history")
    let history = try Self.threeSteps(in: directory)
    let before = history.steps
    try await history.revise(from: 1, label: "b again") { revised in
      try revised.apply(processID: "b2", params: Self.params, result: try Self.image([7, 7, 7, 7]))
    }
    let revised = history.steps
    let first = try #require(history.versions.first)

    try history.restore(version: first.id)

    #expect(history.steps == before && history.current.planes == [[3, 3, 3, 3]])
    let replaced = try #require(history.versions.last)
    #expect(history.versions.count == 1 && replaced.steps == Array(revised[1...]))
    #expect(replaced.base == 1 && replaced.id != first.id)

    try history.restore(version: replaced.id)
    #expect(history.steps == revised && history.current.planes == [[7, 7, 7, 7]])
    #expect(history.versions.map(\.steps) == [Array(before[1...])])

    #expect(throws: HistoryError.unknownVersion("nope")) { try history.restore(version: "nope") }
    let last = try #require(history.versions.last)
    try history.undo()
    try history.undo()
    #expect(throws: HistoryError.versionOutOfReach(last.id)) {
      try history.restore(version: last.id)
    }
  }

  @Test("testRevise_BodyThrowsBeforeApply_LeavesHistoryIntact", .scratchDirectory)
  func testRevise_BodyThrowsBeforeApply_LeavesHistoryIntact() async throws {
    let directory = try ScratchDirectory.url.appendingPathComponent("history")
    let history = try Self.threeSteps(in: directory)
    try history.undo()
    let steps = history.steps
    let undone = history.undone
    let manifest = try Self.manifestData(directory)

    await #expect(throws: Failed()) {
      try await history.revise(from: 0, label: "nothing") { _ in throw Failed() }
    }

    #expect(history.steps == steps && history.undone == undone && history.versions.isEmpty)
    #expect(try Self.manifestData(directory) == manifest)
    #expect(history.current.planes == [[2, 2, 2, 2]])
    await #expect(throws: HistoryError.noStep(2)) {
      try await history.revise(from: 2, label: "past the end") { _ in }
    }
  }

  @Test("testRevise_BodyThrowsAfterApply_KeepsAppliedAndVersion", .scratchDirectory)
  func testRevise_BodyThrowsAfterApply_KeepsAppliedAndVersion() async throws {
    let directory = try ScratchDirectory.url.appendingPathComponent("history")
    let history = try Self.threeSteps(in: directory)
    let before = history.steps

    await #expect(throws: Failed()) {
      try await history.revise(from: 1, label: "half") { revised in
        try revised.apply(
          processID: "y", params: Self.params, result: try Self.image([5, 5, 5, 5]))
        throw Failed()
      }
    }

    #expect(history.steps.map(\.processID) == ["a", "y"])
    #expect(history.versions.map(\.steps) == [Array(before[1...])])
    #expect(history.current.planes == [[5, 5, 5, 5]])
  }

  @Test("testSave_KeepsVersionFiles", .scratchDirectory)
  func testSave_KeepsVersionFiles() async throws {
    let directory = try ScratchDirectory.url.appendingPathComponent("history")
    let history = try Self.threeSteps(in: directory)
    let tail = history.steps[1...].map(\.file)
    try await history.revise(from: 1, label: "v") { revised in
      try revised.apply(processID: "z", params: Self.params, result: try Self.image([8, 8, 8, 8]))
    }

    try history.save()

    #expect(try Self.files(in: directory).isSuperset(of: tail))
    #expect(try Self.files(in: directory) == history.referencedFiles)
  }

  @Test("testDropVersion_ThenSave_RemovesFiles", .scratchDirectory)
  func testDropVersion_ThenSave_RemovesFiles() async throws {
    let directory = try ScratchDirectory.url.appendingPathComponent("history")
    let history = try Self.threeSteps(in: directory)
    let tail = Set(history.steps[1...].map(\.file))
    try await history.revise(from: 1, label: "v") { revised in
      try revised.apply(processID: "z", params: Self.params, result: try Self.image([8, 8, 8, 8]))
    }
    let version = try #require(history.versions.first)

    try history.dropVersion(version.id)
    try history.save()

    #expect(history.versions.isEmpty)
    #expect(try Self.files(in: directory).isDisjoint(with: tail))
    #expect(throws: HistoryError.unknownVersion(version.id)) {
      try history.dropVersion(version.id)
    }
  }

  @Test("testReopen_RestoresVersions", .scratchDirectory)
  func testReopen_RestoresVersions() async throws {
    let directory = try ScratchDirectory.url.appendingPathComponent("history")
    let original = try Self.image([0, 1, 2, 3])
    let history = try Self.threeSteps(in: directory)
    try await history.revise(from: 2, label: "c again") { revised in
      try revised.apply(processID: "c2", params: Self.params, result: try Self.image([6, 6, 6, 6]))
    }

    let reopened = try History.reopen(directory: directory, original: original) { _ in
      Self.gainSchema
    }

    #expect(reopened.versions == history.versions && reopened.steps == history.steps)
    try reopened.restore(version: try #require(reopened.versions.first).id)
    #expect(reopened.current.planes == [[3, 3, 3, 3]])
    // Its files are the reopened history's own: dropped, they go on save.
    let replaced = try #require(reopened.versions.first)
    try reopened.dropVersion(replaced.id)
    try reopened.save()
    #expect(try Self.files(in: directory) == reopened.referencedFiles)
  }
}
