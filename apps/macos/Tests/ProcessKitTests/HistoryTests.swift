import Foundation
import ImageKit
import ProcessKit
import TestSupport
import Testing

@Suite("History: applied steps on disk, undo/redo, snapshots, cleanup on save")
struct HistoryTests {
  static func image(_ values: [Float]) throws -> AstroImage {
    let header = try FITSFile.parse(Data(Self.headerText.utf8)).header
    return AstroImage(width: 2, height: 2, planes: [values], metadata: ImageMetadata(header: header))
  }

  static let headerText: String = {
    var text = ["OBJECT  = 'M31'", "ROWORDER= 'TOP-DOWN'"]
      .map { $0.padding(toLength: 80, withPad: " ", startingAt: 0) }.joined() + "END"
    while text.utf8.count % 2880 != 0 { text += " " }
    return text
  }()

  static let params = ParamSet(schema: ParamSchema([
    ParamSpec(id: "gain", title: "Gain", unit: .none, level: .simple, number: 1, in: 0...8)
  ]))

  static func files(in directory: URL) throws -> Set<String> {
    Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
  }

  @Test("apply A, B → undo gives A back from disk; redo restores B; save removes dropped steps",
    .scratchDirectory)
  func testApplyUndoRedo() throws {
    let directory = try ScratchDirectory.url.appendingPathComponent("history")
    let original = try Self.image([0, 1, 2, 3])
    let header = try FITSFile.parse(Data(Self.headerText.utf8)).header
    let history = try History(directory: directory, original: original, header: header)

    try history.apply(processID: "a", params: Self.params, result: try Self.image([0, 2, 4, 6]))
    try history.apply(processID: "b", params: Self.params, result: try Self.image([1, 3, 5, 7]))
    #expect(history.steps.map(\.processID) == ["a", "b"])

    try history.undo()
    #expect(history.current.planes == [[0, 2, 4, 6]], "A, reloaded from its file")
    #expect(history.current.metadata.object == "M31", "the step keeps the source's cards")
    try history.redo()
    #expect(history.current.planes == [[1, 3, 5, 7]])
    try history.undo()
    try history.undo()
    #expect(history.current.planes == original.planes)
    #expect(!history.canUndo && history.canRedo)

    try history.redo()
    try history.apply(processID: "c", params: Self.params, result: try Self.image([9, 9, 9, 9]))
    #expect(!history.canRedo, "a new step drops what was undone")
    let dropped = try Self.files(in: directory).subtracting(history.referencedFiles)
    #expect(dropped.count == 1, "B's output waits for the save")
    try history.save()
    #expect(try Self.files(in: directory) == history.referencedFiles)
    #expect(history.diskBytes > 0)
    #expect(history.diskBytes == history.referencedFiles.reduce(0) { total, name in
      total + ((try? FileManager.default.attributesOfItem(
        atPath: directory.appendingPathComponent(name).path)[.size] as? Int) ?? 0)
    })
  }

  @Test("a snapshot survives undo, is listed, resolves to its image, and keeps its file on save",
    .scratchDirectory)
  func testSnapshotsSurviveUndo() throws {
    let directory = try ScratchDirectory.url.appendingPathComponent("history")
    let history = try History(directory: directory, original: try Self.image([0, 1, 2, 3]))
    try history.snapshot(name: "original")
    try history.apply(processID: "a", params: Self.params, result: try Self.image([4, 4, 4, 4]))
    try history.snapshot(name: "v9")
    try history.apply(processID: "b", params: Self.params, result: try Self.image([5, 5, 5, 5]))

    try history.undo()
    try history.undo()
    #expect(history.snapshots.map(\.name) == ["original", "v9"])
    #expect(try history.image(snapshot: "v9").planes == [[4, 4, 4, 4]])
    #expect(try history.image(snapshot: "original").planes == [[0, 1, 2, 3]])
    #expect(throws: HistoryError.unknownSnapshot("v10")) { try history.image(snapshot: "v10") }
    #expect(throws: HistoryError.duplicateSnapshot("v9")) { try history.snapshot(name: "v9") }

    try history.apply(processID: "c", params: Self.params, result: try Self.image([6, 6, 6, 6]))
    try history.save()
    #expect(try history.image(snapshot: "v9").planes == [[4, 4, 4, 4]], "A dropped, its file kept")
    #expect(try Self.files(in: directory).count == 2, "C and the v9 snapshot's A")
  }

  @Test("undo with nothing applied and redo with nothing undone are errors", .scratchDirectory)
  func testNothingToUndo() throws {
    let history = try History(
      directory: ScratchDirectory.url.appendingPathComponent("h"), original: try Self.image([0, 0, 0, 0]))
    #expect(throws: HistoryError.nothingToUndo) { try history.undo() }
    #expect(throws: HistoryError.nothingToRedo) { try history.redo() }
  }
}
