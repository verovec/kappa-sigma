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

  /// The process holding the package: pid and start time (a reused pid is another process).
  package let process: ProcessStamp
  /// This opening of the package: `close()` removes the marker only while it still carries its
  /// own token — a reopen by this process (a move, a Save As, a revert) rewrites the marker and
  /// the old instance's close must not take it away.
  package let token: UUID

  package init(process: ProcessStamp, token: UUID = UUID()) {
    self.process = process
    self.token = token
  }

  /// This process, a fresh token; `nil` when this process cannot be stamped.
  static func current() -> Self? {
    ProcessLiveness.current.map { Self(process: $0) }
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

  /// The live owner of `package` that is not this process, if any.
  ///
  /// What refuses an open and a Save As over it; a marker whose process is gone, or ours, holds
  /// nothing.
  package static func heldElsewhere(in package: URL) -> Self? {
    read(in: package).flatMap { $0.heldElsewhere(from: ProcessLiveness.current) }
  }

  /// This owner when it is live and not `me` (nil when this process cannot be stamped: every
  /// live owner is then elsewhere), else `nil`.
  func heldElsewhere(from me: ProcessStamp?) -> Self? {
    isLive && process != me ? self : nil
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

  /// Removes the marker from `package` when it is the one `token` wrote; another opening's stays.
  package static func release(_ token: UUID, in package: URL) {
    guard read(in: package)?.token == token else { return }
    remove(in: package)
  }
}
