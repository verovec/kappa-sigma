package import Foundation

/// Who holds a project open (card 0147): a marker next to `project.db`, written by
/// `ProjectPackage.open(at:owning:)` and removed by `close()`.
///
/// Two instances of the app each holding a `DatabasePool` on one `project.db` show two stale
/// stack lists; the marker lets the second refuse with a reason. Its name is not StackKit's
/// scratch `owner.json`: `LeftoverSweep` reads that one and must never meet this one.
package struct ProjectOwner: Codable, Equatable, Sendable {
  /// The marker's file name inside the package.
  package static let fileName = "project-owner.json"

  /// The process holding the package.
  package let process: ProcessStamp
  /// The app bundle that process runs (a hint for the message, never a rule).
  package let bundlePath: String
  /// When it took the package, Unix milliseconds.
  package let startedAtMs: Int64

  package init(process: ProcessStamp, bundlePath: String, startedAtMs: Int64) {
    self.process = process
    self.bundlePath = bundlePath
    self.startedAtMs = startedAtMs
  }

  /// This process, now.
  static func current() -> Self? {
    ProcessLiveness.current.map {
      Self(
        process: $0, bundlePath: Bundle.main.bundlePath,
        startedAtMs: Int64(Date().timeIntervalSince1970 * 1000))
    }
  }

  /// Whether the owner's process still runs.
  package var isLive: Bool { ProcessLiveness.isRunning(process) }

  /// The marker's path in `package`.
  static func url(in package: URL) -> URL { package.appendingPathComponent(fileName) }

  /// The marker in `package`, or `nil` (none, or unreadable: treated as none).
  package static func read(in package: URL) -> Self? {
    guard let data = try? Data(contentsOf: url(in: package)) else { return nil }
    return try? JSONDecoder().decode(Self.self, from: data)
  }

  /// Writes the marker into `package`, atomically, keys sorted (a stable file).
  package func write(in package: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    try encoder.encode(self).write(to: Self.url(in: package), options: .atomic)
  }

  /// Removes the marker from `package`, if any.
  package static func remove(in package: URL) {
    try? FileManager.default.removeItem(at: url(in: package))
  }
}
