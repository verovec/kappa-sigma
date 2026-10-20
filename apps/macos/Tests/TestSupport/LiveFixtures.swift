package import Foundation
package import Testing

/// The live fixture root: images and recordings derived from captures, outside every repo (R7).
///
/// Live suites (name starting with `Live`) carry `.liveFixtures` and `.tags(.live)`; they show as
/// skipped, never green, where the root is absent (CI, a fresh clone). See testing-conventions.md.
package enum LiveFixtures {
  /// `<home>/Documents/astro/fixtures` when it is a folder, `nil` otherwise.
  package static func root(home: URL) -> URL? {
    root(home: home, environment: [:])
  }

  /// As `root(home:)`, but `nil` when `ASTROSTACK_SKIP_LIVE=1`: CI on the PO's Mac (self-hosted
  /// runner) has the fixtures on disk yet runs exactly what the hosted runner runs.
  package static func root(home: URL, environment: [String: String]) -> URL? {
    guard environment["ASTROSTACK_SKIP_LIVE"] != "1" else { return nil }
    let root = home.appendingPathComponent("Documents/astro/fixtures", isDirectory: true)
    let isFolder = (try? root.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory
    return isFolder == true ? root : nil
  }

  /// The root for the current user (`$HOME`), or `nil`.
  package static var root: URL? {
    let home = ProcessInfo.processInfo.environment["HOME"].map { URL(fileURLWithPath: $0) }
    return root(
      home: home ?? FileManager.default.homeDirectoryForCurrentUser,
      environment: ProcessInfo.processInfo.environment)
  }
}

extension Tag {
  /// Tests that need host tools or `~/Documents/astro/fixtures`; never run on CI.
  @Tag package static var live: Self
}

extension Trait where Self == ConditionTrait {
  /// Skips, with the reason, when `~/Documents/astro/fixtures` is absent.
  package static var liveFixtures: Self {
    .enabled(if: LiveFixtures.root != nil, "~/Documents/astro/fixtures absent")
  }
}
