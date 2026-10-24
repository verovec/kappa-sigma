import AstroStackApp
import Foundation
import ProjectKit
import StackKit
import TestSupport
import Testing

/// What a run that did not finish leaves in `stacks/`: removed when nothing finished, else shown
/// for the user to delete (card 0113).
@MainActor
@Suite("Run leftovers — stack folders no stack records")
struct RunLeftoversTests {
  enum Failure: Error { case siril }

  /// A run that writes `files` into its output, then ends with `error`.
  static func failingRun(writing files: [String], error: any Error) -> RunServices.Run {
    { request in
      AsyncThrowingStream(PreprocessEvent.self) { continuation in
        try? FileManager.default.createDirectory(
          at: request.output, withIntermediateDirectories: true)
        for file in files {
          try? Data(count: 4096).write(to: request.output.appendingPathComponent(file))
        }
        continuation.finish(throwing: error)
      }
    }
  }

  var output: URL {
    get throws {
      try ScratchDirectory.url.appendingPathComponent("M31.astrostack/stacks/\(ProjectTests.runID)")
    }
  }

  @Test("a failed run with nothing finished leaves no stack folder", .scratchDirectory)
  func testFailedRunRemovesEmptyBundle() async throws {
    let fixture = try ProjectTests.fixture(
      run: Self.failingRun(writing: ["master_L_preview.png"], error: Failure.siril))
    defer { try? fixture.project.close() }
    fixture.window.add(ImportRequest(paths: ["/c/M31-DB"]))
    fixture.window.startRun()
    await fixture.window.run?.settled()

    guard case .failed = fixture.window.run?.phase else {
      Issue.record("the run did not fail: \(String(describing: fixture.window.run?.phase))")
      return
    }
    #expect(!FileManager.default.fileExists(atPath: try output.path))
    #expect(fixture.window.leftoverStacks.isEmpty)
  }

  @Test(
    "a cancelled run keeps its finished masters, shown as a stack folder to delete",
    .scratchDirectory)
  func testCancelledRunKeepsMastersListed() async throws {
    let fixture = try ProjectTests.fixture(
      run: Self.failingRun(writing: ["master_R.fits"], error: CancellationError()))
    defer { try? fixture.project.close() }
    fixture.window.add(ImportRequest(paths: ["/c/M31-DB"]))
    fixture.window.startRun()
    await fixture.window.run?.settled()

    #expect(
      FileManager.default.fileExists(
        atPath: try output.appendingPathComponent("master_R.fits").path))
    let leftover = try #require(fixture.window.leftoverStacks.first)
    #expect(leftover.path == "stacks/\(ProjectTests.runID)")

    fixture.window.deleteLeftoverStack(leftover)

    #expect(!FileManager.default.fileExists(atPath: try output.path))
    #expect(fixture.window.leftoverStacks.isEmpty)
  }

  @Test("a Delete the package refuses is shown, nothing removed", .scratchDirectory)
  func testRefusedDeleteShown() throws {
    let project = try ProjectPackage.create(
      at: try ScratchDirectory.url.appendingPathComponent("M31.astrostack"))
    defer { try? project.close() }
    let window = ProjectWindowModel(store: { project.store }, folder: { project.url })

    window.deleteLeftoverStack(LeftoverStack(path: "project.db", bytes: 0))

    #expect(window.error != nil)
    #expect(
      FileManager.default.fileExists(atPath: project.url.appendingPathComponent("project.db").path))
  }

  @Test(
    "opening a project lists its unrecorded stack folders and removes the empty ones",
    .scratchDirectory)
  func testOrphanStackFolderListedAtOpen() async throws {
    let scratch = try ScratchDirectory.url
    let project = try ProjectPackage.create(at: scratch.appendingPathComponent("M31.astrostack"))
    defer { try? project.close() }
    let stacks = project.url.appendingPathComponent("stacks")
    let empty = stacks.appendingPathComponent("20261020_210000")
    let kept = stacks.appendingPathComponent("20261020_220000")
    for folder in [empty, kept] {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    try Data(count: 4096).write(to: kept.appendingPathComponent("master_G.fits"))

    let window = ProjectWindowModel(store: { project.store }, folder: { project.url })

    #expect(window.leftoverStacks.map(\.path) == ["stacks/20261020_220000"])
    #expect(!FileManager.default.fileExists(atPath: empty.path))
    #expect(FileManager.default.fileExists(atPath: kept.path))
  }
}
