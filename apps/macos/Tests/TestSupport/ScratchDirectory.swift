package import Foundation
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
  // Other worktrees and the CI runner share the folder, so the sweep only takes stale entries.
  private static let sweep: Void = removeStale(in: root, olderThan: staleAge, now: Date())

  /// Creates the directory under the temporary folder, runs the test with it, then removes it.
  @concurrent
  package func provideScope(
    for test: Test, testCase: Test.Case?,
    performing function: @concurrent @Sendable () async throws -> Void
  ) async throws {
    Self.sweep
    let directory = Self.root.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try await Self.$current.withValue(directory) { try await function() }
  }

  /// Removes the entries of `folder` last modified more than `age` seconds before `now`.
  package static func removeStale(in folder: URL, olderThan age: TimeInterval, now: Date) {
    let manager = FileManager.default
    let entries =
      (try? manager.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
    for entry in entries {
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
