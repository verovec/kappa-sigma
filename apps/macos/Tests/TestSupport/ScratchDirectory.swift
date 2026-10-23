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

  /// Unmarked leftovers older than this belong to no running test: a killed run never reached
  /// its cleanup. A marked one goes as soon as the test process that made it is gone.
  package static let staleAge: TimeInterval = LeftoverSweep.staleAge

  // Live preprocessing tests write tens of GB each, so a directory left behind fills the disk
  // within a day. Removing it at the end is cleanup, not reset: every test still starts empty.
  // Other worktrees and the CI runner share the folder, so the sweep only takes entries whose
  // test process is gone (each directory carries its marker), and what a killed test's Siril
  // or untitled project left in the app's scratch folders.
  private static let sweep: Void = {
    removeStale(in: root, olderThan: staleAge, now: Date())
    LeftoverSweep(roots: LeftoverSweep.appRoots()).run()
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
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try ScratchOwner.mark(owned)
    defer { try? FileManager.default.removeItem(at: owned) }
    try await Self.$current.withValue(directory) { try await function() }
  }

  /// Removes the entries of `folder` whose test process is gone, and the unmarked ones last
  /// modified more than `age` seconds before `now`.
  package static func removeStale(in folder: URL, olderThan age: TimeInterval, now: Date) {
    LeftoverSweep(roots: [.init(folder: folder, prefix: "")], now: now, unmarkedAge: age).run()
  }
}

extension Trait where Self == ScratchDirectory {
  /// A fresh, empty directory for each test (or each test case of a parameterised test).
  package static var scratchDirectory: Self { Self() }
}
