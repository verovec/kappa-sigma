import Foundation
import StackKit
import TestSupport
import Testing

@Suite("StackLeftovers — a failed run's folder and stack folders no stack records")
struct RunCleanupTests {
  /// `stacks/<name>/` of `package` holding `files` (4 KiB each).
  static func stack(_ name: String, in package: URL, files: [String]) throws -> URL {
    let folder = package.appendingPathComponent("stacks/\(name)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for file in files { try Data(count: 4096).write(to: folder.appendingPathComponent(file)) }
    return folder
  }

  static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

  @Test(
    "a failed run's folder goes unless it holds a finished master",
    .scratchDirectory,
    arguments: [
      ([], false),
      (["master_L_preview.png", "grades.json"], false),
      (["master_L.fits", "master_L_preview.png"], true),
    ])
  func testFailedRunRemovesEmptyBundle(_ files: [String], kept: Bool) async throws {
    let folder = try Self.stack("20261023_210000", in: try ScratchDirectory.url, files: files)

    let removal = await StackLeftovers.removeUnfinished(folder)

    #expect(Self.exists(folder) == kept)
    #expect((removal == nil) == kept)
    #expect(removal.map { $0.bytes >= Int64(files.count) * 4096 } ?? true)
  }

  @Test(
    "a stack folder no stack records: removed when empty, listed when it holds files",
    .scratchDirectory)
  func testOrphanStackFolderListed() throws {
    let package = try ScratchDirectory.url.appendingPathComponent("M31.astrostack")
    let recorded = try Self.stack("20261021_210000", in: package, files: ["bundle.json"])
    let empty = try Self.stack("20261022_210000", in: package, files: [])
    let failed = try Self.stack("20261022_220000", in: package, files: ["master_R.fits"])

    let orphans = StackLeftovers.orphans(in: package, recorded: ["stacks/20261021_210000"])

    #expect(orphans.map(\.path) == ["stacks/20261022_220000"])
    #expect(orphans.first.map { $0.bytes >= 4096 } == true)
    #expect(Self.exists(recorded) && Self.exists(failed), "files are offered, never removed")
    #expect(!Self.exists(empty))

    try StackLeftovers.remove(try #require(orphans.first), in: package)
    #expect(!Self.exists(failed))
  }

  @Test("a folder a run still holds is judged once the run lets go, else kept", .scratchDirectory)
  func testWaitsForTheRunToLetGo() async throws {
    let folder = try Self.stack("20261023_220000", in: try ScratchDirectory.url, files: [])
    try TargetLock.acquire(folder)

    #expect(await StackLeftovers.removeUnfinished(folder, wait: .milliseconds(100)) == nil)
    #expect(Self.exists(folder), "another run's folder, or a teardown still writing, stays")

    let late = Task { await StackLeftovers.removeUnfinished(folder, wait: .seconds(30)) }
    // The run lets go before or while the removal waits: either way the folder is judged then.
    TargetLock.release(folder)
    #expect(await late.value != nil)
    #expect(!Self.exists(folder))
  }

  @Test("a folder holding only the Finder's .DS_Store counts as empty", .scratchDirectory)
  func testFinderFilesAreEmpty() throws {
    let package = try ScratchDirectory.url.appendingPathComponent("M31.astrostack")
    let browsed = try Self.stack("20261022_230000", in: package, files: [".DS_Store"])

    #expect(StackLeftovers.orphans(in: package, recorded: []).isEmpty)
    #expect(!Self.exists(browsed))
  }

  @Test("a stack folder a run still holds is neither listed nor removed", .scratchDirectory)
  func testHeldFolderLeftAlone() throws {
    let package = try ScratchDirectory.url.appendingPathComponent("M31.astrostack")
    let running = try Self.stack("20261024_010000", in: package, files: [])
    try TargetLock.acquire(running)
    defer { TargetLock.release(running) }

    #expect(StackLeftovers.orphans(in: package, recorded: []).isEmpty)
    #expect(Self.exists(running))
  }

  @Test("a package without stacks has no leftovers", .scratchDirectory)
  func testNoStacksFolder() throws {
    #expect(StackLeftovers.orphans(in: try ScratchDirectory.url, recorded: []).isEmpty)
  }

  @Test("only a stack folder of the package can be removed", .scratchDirectory)
  func testRemoveRefusesOtherPaths() throws {
    let package = try ScratchDirectory.url.appendingPathComponent("M31.astrostack")
    try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
    for path in ["project.db", "stacks/../project.db", "stacks", "../M31.astrostack"] {
      #expect(throws: StackLeftovers.Refusal.self) {
        try StackLeftovers.remove(LeftoverStack(path: path, bytes: 0), in: package)
      }
    }
    #expect(Self.exists(package))
  }
}
