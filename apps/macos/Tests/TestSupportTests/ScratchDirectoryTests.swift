import Foundation
import StackKit
import TestSupport
import Testing

@Suite("ScratchDirectory starts empty and leaves nothing behind")
struct ScratchDirectoryTests {
  @Test("the scratch directory is removed once the test returns")
  func testScratchDirectory_scope_removedAfterTest() async throws {
    let (trait, test) = (ScratchDirectory.scratchDirectory, try #require(Test.current))
    let seen = Seen()
    try await trait.provideScope(for: test, testCase: nil) {
      let url = try ScratchDirectory.url
      try Data([1, 2, 3]).write(to: url.appendingPathComponent("frame.fits"))
      seen.set(url)
    }
    let url = try #require(seen.get())
    #expect(!FileManager.default.fileExists(atPath: url.path))
  }

  @Test("the scratch directory is removed when the test throws")
  func testScratchDirectory_scope_removedAfterThrow() async throws {
    let (trait, test) = (ScratchDirectory.scratchDirectory, try #require(Test.current))
    let seen = Seen()
    await #expect(throws: CancellationError.self) {
      try await trait.provideScope(for: test, testCase: nil) {
        seen.set(try ScratchDirectory.url)
        throw CancellationError()
      }
    }
    let url = try #require(seen.get())
    #expect(!FileManager.default.fileExists(atPath: url.path))
  }

  @Test("the sweep removes only entries older than the stale age", .scratchDirectory)
  func testScratchDirectory_removeStale_keepsRecent() throws {
    let folder = try ScratchDirectory.url
    let now = Date()
    let old = folder.appendingPathComponent("old", isDirectory: true)
    let recent = folder.appendingPathComponent("recent", isDirectory: true)
    for entry in [old, recent] {
      try FileManager.default.createDirectory(at: entry, withIntermediateDirectories: true)
    }
    try FileManager.default.setAttributes(
      [.modificationDate: now.addingTimeInterval(-ScratchDirectory.staleAge - 60)],
      ofItemAtPath: old.path)

    ScratchDirectory.removeStale(in: folder, olderThan: ScratchDirectory.staleAge, now: now)

    #expect(!FileManager.default.fileExists(atPath: old.path))
    #expect(FileManager.default.fileExists(atPath: recent.path))
  }

  @Test("a test's scratch directory starts empty, in a folder the test process marks")
  func testScratchDirectory_scope_markedByThisProcess() async throws {
    let (trait, test) = (ScratchDirectory.scratchDirectory, try #require(Test.current))
    try await trait.provideScope(for: test, testCase: nil) {
      let url = try ScratchDirectory.url
      #expect(try FileManager.default.contentsOfDirectory(atPath: url.path).isEmpty)
      let owned = url.deletingLastPathComponent()
      #expect(owned.deletingLastPathComponent() == ScratchDirectory.root)
      #expect(ScratchOwner.read(owned)?.owner.pid == getpid())
      #expect(ScratchOwner.read(owned)?.isAlive(in: .live) == true)
    }
  }

  @Test("the age sweep keeps a folder whose test process still runs", .scratchDirectory)
  func testScratchDirectory_removeStale_keepsLiveOwners() throws {
    let folder = try ScratchDirectory.url
    let running = folder.appendingPathComponent("running", isDirectory: true)
    try FileManager.default.createDirectory(at: running, withIntermediateDirectories: true)
    try ScratchOwner.mark(running)
    try FileManager.default.setAttributes(
      [.modificationDate: Date().addingTimeInterval(-ScratchDirectory.staleAge - 60)],
      ofItemAtPath: running.path)

    ScratchDirectory.removeStale(in: folder, olderThan: ScratchDirectory.staleAge, now: Date())

    #expect(FileManager.default.fileExists(atPath: running.path))
  }

  @Test("the sweep takes a killed test's directory at once, however recent", .scratchDirectory)
  func testScratchDirectory_removeDead_takesDeadOwners() throws {
    let folder = try ScratchDirectory.url
    let killed = folder.appendingPathComponent("killed", isDirectory: true)
    try FileManager.default.createDirectory(at: killed, withIntermediateDirectories: true)
    // pid 0 is the kernel's: no test process ever had it.
    try ScratchOwner(owner: ProcessIdentity(pid: 0, startSeconds: 1, startMicroseconds: 0))
      .write(to: killed)

    let unmarked = folder.appendingPathComponent("unmarked", isDirectory: true)
    try FileManager.default.createDirectory(at: unmarked, withIntermediateDirectories: true)

    ScratchDirectory.removeDead(in: folder)

    #expect(!FileManager.default.fileExists(atPath: killed.path))
    #expect(FileManager.default.fileExists(atPath: unmarked.path), "no marker: left to its age")
  }
}

/// The URL a scope saw, read back after the scope has returned.
private final class Seen: @unchecked Sendable {
  private let lock = NSLock()
  private var url: URL?
  func set(_ value: URL) { lock.withLock { url = value } }
  func get() -> URL? { lock.withLock { url } }
}
