import Foundation
import ImageKit
import ProcessKit
import TestSupport
import Testing

/// The edges of history versions (card 0156): a version restores only on the step it was
/// computed on, undone steps are kept, ids are never reused, a bad manifest is refused.
extension HistoryTests {
  @Test("a version is out of reach once the steps before it changed", .scratchDirectory)
  func testRestore_RefusesAnotherParent() async throws {
    let directory = try ScratchDirectory.url.appendingPathComponent("history")
    let history = try Self.threeSteps(in: directory)
    try await history.revise(from: 2, label: "c") { revised in
      try revised.apply(processID: "c2", params: Self.params, result: try Self.image([4, 4, 4, 4]))
    }
    let onB = try #require(history.versions.first)
    try await history.revise(from: 0, label: "all") { revised in
      try revised.apply(processID: "x", params: Self.params, result: try Self.image([5, 5, 5, 5]))
      try revised.apply(processID: "y", params: Self.params, result: try Self.image([6, 6, 6, 6]))
    }

    // Two steps again, but `c` was computed on b, not on y.
    #expect(throws: HistoryError.versionOutOfReach(onB.id)) {
      try history.restore(version: onB.id)
    }
    #expect(history.steps.map(\.processID) == ["x", "y"])
  }

  @Test(
    "revise and restore keep the undone steps in the version; no empty version", .scratchDirectory)
  func testVersions_KeepUndone() async throws {
    let directory = try ScratchDirectory.url.appendingPathComponent("history")
    let history = try Self.threeSteps(in: directory)
    let before = history.steps
    try history.undo()

    try await history.revise(from: 1, label: "b") { revised in
      try revised.apply(processID: "x", params: Self.params, result: try Self.image([5, 5, 5, 5]))
      try revised.apply(processID: "y", params: Self.params, result: try Self.image([6, 6, 6, 6]))
    }
    #expect(history.versions.map(\.steps) == [Array(before[1...])], "c, undone, kept")
    let first = try #require(history.versions.first)

    try history.undo()
    try history.undo()
    try history.restore(version: first.id)
    // c comes back undone, as it was put aside (card 0157); x and y were both undone: the
    // replaced version holds them, in apply order.
    #expect(history.steps == Array(before[..<2]) && history.undone == [before[2]])
    #expect(history.versions.map { $0.steps.map(\.processID) } == [["x", "y"]])
    #expect(history.versions.first?.redo == 2)
    try history.save()
    #expect(try Self.files(in: directory) == history.referencedFiles)

    // Restored, x and y are undone again: two redos bring them back; no version is empty.
    let back = try #require(history.versions.first)
    try history.restore(version: back.id)
    #expect(history.steps.map(\.processID) == ["a"])
    #expect(history.undone.map(\.processID) == ["y", "x"])
    try history.redo()
    try history.redo()
    #expect(history.steps.map(\.processID) == ["a", "x", "y"])
    #expect(history.versions.allSatisfy { !$0.steps.isEmpty })
  }

  @Test("a version id is never used twice, across a drop and a reopen", .scratchDirectory)
  func testVersionIDs_NeverReused() async throws {
    let directory = try ScratchDirectory.url.appendingPathComponent("history")
    let history = try Self.threeSteps(in: directory)
    try await history.revise(from: 2, label: "one") { revised in
      try revised.apply(processID: "p", params: Self.params, result: try Self.image([4, 4, 4, 4]))
    }
    let first = try #require(history.versions.last).id
    try history.dropVersion(first)

    let reopened = try History.reopen(
      directory: directory, original: try Self.image([0, 1, 2, 3])
    ) { _ in Self.gainSchema }
    try await reopened.revise(from: 2, label: "two") { revised in
      try revised.apply(processID: "q", params: Self.params, result: try Self.image([5, 5, 5, 5]))
    }
    #expect(try #require(reopened.versions.last).id != first)
  }

  @Test(
    "a body that applied then undid a step keeps it: the revise is not rolled back",
    .scratchDirectory)
  func testRevise_AppliedThenUndone_Kept() async throws {
    let directory = try ScratchDirectory.url.appendingPathComponent("history")
    let history = try Self.threeSteps(in: directory)

    await #expect(throws: Failed()) {
      try await history.revise(from: 1, label: "z") { revised in
        try revised.apply(
          processID: "z", params: Self.params, result: try Self.image([5, 5, 5, 5]))
        try revised.undo()
        throw Failed()
      }
    }

    #expect(history.steps.map(\.processID) == ["a"])
    #expect(history.undone.map(\.processID) == ["z"] && history.versions.count == 1)
  }

  @Test("a manifest whose version base is negative is refused on reopen", .scratchDirectory)
  func testReopen_RefusesBadVersionBase() async throws {
    let directory = try ScratchDirectory.url.appendingPathComponent("history")
    let history = try Self.threeSteps(in: directory)
    try await history.revise(from: 1, label: "v") { revised in
      try revised.apply(processID: "x", params: Self.params, result: try Self.image([5, 5, 5, 5]))
    }
    let url = directory.deletingLastPathComponent().appendingPathComponent("history.json")
    let text = try #require(String(bytes: try Data(contentsOf: url), encoding: .utf8))
    try Data(text.replacingOccurrences(of: "\"base\" : 1", with: "\"base\" : -1").utf8)
      .write(to: url)

    #expect(throws: HistoryError.unreadable("version v1 base")) {
      _ = try History.reopen(directory: directory, original: try Self.image([0, 1, 2, 3])) { _ in
        Self.gainSchema
      }
    }
  }

  @Test("a revise after an undo is undone back to that very state (card 0157)", .scratchDirectory)
  func testRestore_AfterUndo_PutsUndoneBack() async throws {
    let directory = try ScratchDirectory.url.appendingPathComponent("history")
    let history = try Self.threeSteps(in: directory)
    try history.undo()
    let (steps, undone, head) = (history.steps, history.undone, history.current.planes)
    try await history.revise(from: 1, label: "b") { revised in
      try revised.apply(processID: "x", params: Self.params, result: try Self.image([5, 5, 5, 5]))
    }
    let id = try #require(history.versions.last).id

    let replaced = try history.restore(version: id, replacedLabel: "revised")

    #expect(history.steps == steps && history.undone == undone)
    #expect(history.current.planes == head)
    #expect(history.versions.last?.id == replaced && history.versions.last?.label == "revised")
    let reopened = try History.reopen(
      directory: directory, original: try Self.image([0, 1, 2, 3])
    ) { _ in Self.gainSchema }
    #expect(reopened.versions == history.versions && reopened.undone == undone)
  }
}
