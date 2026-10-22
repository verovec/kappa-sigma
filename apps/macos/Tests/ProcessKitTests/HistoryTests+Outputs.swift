import Foundation
import ImageKit
import ProcessKit
import TestSupport
import Testing

extension HistoryTests {
  /// The schema of `params` (`ParamSet` keeps its own private).
  static let gainSchema = ParamSchema([
    ParamSpec(id: "gain", title: "Gain", unit: .none, level: .simple, number: 1, in: 0...8)
  ])

  /// Card 0087: a step may write layers besides its image (StarNet's starless, a background
  /// model); they overlay the bundle for the steps after it, undo takes them away, a reopened
  /// history finds its steps and outputs again, and `save` keeps the referenced outputs only.
  @Test("testStepOutputsRoundTrip", .scratchDirectory)
  func testStepOutputsRoundTrip() throws {
    let directory = try ScratchDirectory.url.appendingPathComponent("history")
    let original = try Self.image([0, 1, 2, 3])
    let header = try FITSFile.parse(Data(Self.headerText.utf8)).header
    let history = try History(directory: directory, original: original, header: header)

    try history.apply(
      processID: "stars", params: Self.params, result: try Self.image([1, 1, 1, 1]),
      outputs: [.starless: try Self.image([5, 5, 5, 5])])
    #expect(history.steps.last?.outputs.keys.sorted { $0.rawValue < $1.rawValue } == [.starless])
    #expect(try history.layers()[.starless]?.planes == [[5, 5, 5, 5]])

    // A later step without outputs keeps the earlier layer; one with the same role replaces it.
    try history.apply(processID: "a", params: Self.params, result: try Self.image([2, 2, 2, 2]))
    #expect(try history.layers()[.starless]?.planes == [[5, 5, 5, 5]])
    try history.apply(
      processID: "stars", params: Self.params, result: try Self.image([3, 3, 3, 3]),
      outputs: [.starless: try Self.image([6, 6, 6, 6])])
    #expect(try history.layers()[.starless]?.planes == [[6, 6, 6, 6]])

    try history.undo()
    #expect(try history.layers()[.starless]?.planes == [[5, 5, 5, 5]], "undo restores the older")
    try history.undo()
    try history.undo()
    #expect(try history.layers().isEmpty, "back at the original: no step output")
    try history.redo()
    try history.redo()
    try history.snapshot(name: "v1")

    // Reopened from the folder: steps, undone, snapshots, outputs and the head come back.
    let reopened = try History.reopen(
      directory: directory, original: original, header: header
    ) { _ in Self.gainSchema }
    #expect(reopened.steps == history.steps && reopened.undone == history.undone)
    #expect(reopened.snapshots == history.snapshots)
    #expect(reopened.current.planes == [[2, 2, 2, 2]])
    #expect(try reopened.layers()[.starless]?.planes == [[5, 5, 5, 5]])
    try reopened.redo()
    #expect(try reopened.layers()[.starless]?.planes == [[6, 6, 6, 6]])

    // A new step drops the undone one; save removes its image and its output, keeps the rest.
    try reopened.undo()
    try reopened.apply(processID: "b", params: Self.params, result: try Self.image([4, 4, 4, 4]))
    let before = try Self.files(in: directory)
    try reopened.save()
    let removed = before.subtracting(try Self.files(in: directory))
    #expect(removed.count == 2, "the dropped step's image and its starless: \(removed)")
    #expect(reopened.referencedFiles.isSubset(of: try Self.files(in: directory)))
    #expect(try reopened.layers()[.starless]?.planes == [[5, 5, 5, 5]])
  }

  @Test("a folder without a manifest reopens as a fresh history", .scratchDirectory)
  func testReopenWithoutManifest() throws {
    let directory = try ScratchDirectory.url.appendingPathComponent("history")
    let original = try Self.image([0, 1, 2, 3])
    let reopened = try History.reopen(directory: directory, original: original) { _ in nil }
    #expect(reopened.steps.isEmpty && reopened.current.planes == original.planes)
  }
}

extension HistoryTests {
  /// The manifest is written before the history moves: when it cannot be written, apply and
  /// undo throw and the history is as it was.
  @Test("a manifest that cannot be written leaves the history unchanged", .scratchDirectory)
  func testManifestFailureLeavesHistory() throws {
    let directory = try ScratchDirectory.url.appendingPathComponent("history")
    let history = try History(directory: directory, original: try Self.image([0, 1, 2, 3]))
    try history.apply(processID: "a", params: Self.params, result: try Self.image([1, 1, 1, 1]))
    // A folder where the manifest file goes: every write of it fails.
    let manifest = directory.deletingLastPathComponent().appendingPathComponent("history.json")
    try FileManager.default.removeItem(at: manifest)
    try FileManager.default.createDirectory(at: manifest, withIntermediateDirectories: false)
    #expect(throws: (any Error).self) {
      try history.apply(processID: "b", params: Self.params, result: try Self.image([2, 2, 2, 2]))
    }
    #expect(history.steps.map(\.processID) == ["a"] && history.current.planes == [[1, 1, 1, 1]])
    #expect(throws: (any Error).self) { try history.undo() }
    #expect(history.steps.count == 1 && history.current.planes == [[1, 1, 1, 1]])
  }
}

extension HistoryTests {
  /// A manifest naming a process or a layer role this build does not know is refused, never
  /// read as another history.
  @Test("a manifest with an unknown process or layer role is unreadable", .scratchDirectory)
  func testReopenRefusesUnknownEntries() throws {
    let directory = try ScratchDirectory.url.appendingPathComponent("history")
    let original = try Self.image([0, 1, 2, 3])
    let history = try History(directory: directory, original: original)
    try history.apply(
      processID: "a", params: Self.params, result: try Self.image([1, 1, 1, 1]),
      outputs: [.starless: try Self.image([6, 6, 6, 6])])
    #expect(throws: HistoryError.unreadable("unknown process a")) {
      _ = try History.reopen(directory: directory, original: original) { _ in nil }
    }
    let manifest = directory.deletingLastPathComponent().appendingPathComponent("history.json")
    let text = try String(contentsOf: manifest, encoding: .utf8)
    try text.replacingOccurrences(of: "\"starless\"", with: "\"moon\"")
      .write(to: manifest, atomically: true, encoding: .utf8)
    #expect(throws: HistoryError.unreadable("unknown layer role moon")) {
      _ = try History.reopen(directory: directory, original: original) { _ in Self.gainSchema }
    }
  }
}
