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

  /// Creates the directory under the temporary folder, then runs the test with it.
  @concurrent
  package func provideScope(
    for test: Test, testCase: Test.Case?,
    performing function: @concurrent @Sendable () async throws -> Void
  ) async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("AstroStackTests", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try await Self.$current.withValue(root) { try await function() }
  }
}

extension Trait where Self == ScratchDirectory {
  /// A fresh, empty directory for each test (or each test case of a parameterised test).
  package static var scratchDirectory: Self { Self() }
}
