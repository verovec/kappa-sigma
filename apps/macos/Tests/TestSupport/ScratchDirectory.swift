package import Foundation
internal import StackKit
package import Testing

/// A fresh, empty directory per test, created before the test runs (clean state at the start,
/// testing-conventions.md). Use `@Test(.scratchDirectory)` and read `ScratchDirectory.url`.
package struct ScratchDirectory: TestTrait, TestScoping {
  /// The current test's scratch directory; `nil` outside a test using the trait.
  @TaskLocal package static var current: URL?

  /// The current test's scratch directory, or a failure when the trait is missing.
  package static var url: URL {
    get throws { try #require(current, "the test needs the .scratchDirectory trait") }
  }

  /// The folder holding every test's scratch directory.
  package static let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("AstroStackTests", isDirectory: true)

  /// Leftovers older than this belong to no running test: a killed run never reached its cleanup.
  package static let staleAge: TimeInterval = 24 * 3600

  // Live preprocessing tests write tens of GB each, so a directory left behind fills the disk
  // within a day. Removing it at the end is cleanup, not reset: every test still starts empty.
  // Other worktrees and the CI runner share the folder, so the sweep only takes stale entries,
  // and at once those whose test process is gone (each carries its marker). Never the app's own
  // scratch folders: a test process sweeps only what tests make (the app's launch sweep reaps
  // a killed test's Siril folder).
  private static let sweep: Void = {
    removeStale(in: root, olderThan: staleAge, now: Date())
    removeDead(in: root)
  }()

  /// Creates the directory under the temporary folder, runs the test with it, then removes it.
  @concurrent
  package func provideScope(
    for test: Test, testCase: Test.Case?,
    performing function: @concurrent @Sendable () async throws -> Void
  ) async throws {
    Self.sweep
    // The marker sits beside the test's directory, never in it: the test starts empty.
    let owned = Self.root.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let directory = owned.appendingPathComponent("test", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: owned) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try ScratchOwner.mark(owned)
    try await Self.$current.withValue(directory) { try await function() }
  }

  /// Removes the marked directories of `folder` whose test process is gone.
  package static func removeDead(in folder: URL) {
    LeftoverSweep(roots: [.init(folder: folder, prefix: "")]).run()
  }

  /// Removes the entries of `folder` last modified more than `age` seconds before `now`.
  ///
  /// Only ever called on the tests' own folder (`root`): an age says nothing about who made an
  /// entry, so the app's sweep never uses one (LeftoverSweep).
  package static func removeStale(in folder: URL, olderThan age: TimeInterval, now: Date) {
    let manager = FileManager.default
    let entries =
      (try? manager.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
    // A folder whose test process still runs is kept, however old (a long live suite).
    for entry in entries where ScratchOwner.read(entry)?.isAlive(in: .live) != true {
      let modified = try? entry.resourceValues(forKeys: [.contentModificationDateKey])
        .contentModificationDate
      if let modified, now.timeIntervalSince(modified) > age { try? manager.removeItem(at: entry) }
    }
  }
}

extension Trait where Self == ScratchDirectory {
  /// A fresh, empty directory for each test (or each test case of a parameterised test).
  package static var scratchDirectory: Self { Self() }
}
