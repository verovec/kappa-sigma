package import Foundation

/// The marker (`owner.json`) a scratch folder carries.
///
/// It names the process that created the folder and the Siril it launched there, if any. A
/// folder whose owner no longer runs is a leftover the sweep may take (`LeftoverSweep`); one
/// whose owner runs is never touched.
package struct ScratchOwner: Codable, Equatable, Sendable {
  /// The marker's file name inside the folder it marks.
  package static let fileName = "owner.json"

  /// The process that created the folder.
  package var owner: ProcessIdentity
  /// The Siril process working in the folder, recorded once it launched.
  package var siril: ProcessIdentity?
  /// The program that Siril runs (`SIRIL_BIN` may name any), recorded with it.
  package var sirilExecutable: String?

  /// A marker from its parts.
  package init(
    owner: ProcessIdentity, siril: ProcessIdentity? = nil, sirilExecutable: String? = nil
  ) {
    self.owner = owner
    self.siril = siril
    self.sirilExecutable = sirilExecutable
  }

  /// True while the owner runs: its pid is taken by a process started when it was.
  package func isAlive(in table: ProcessTable) -> Bool {
    table.identity(owner.pid) == owner
  }

  /// Writes this marker into `folder`, replacing any.
  package func write(to folder: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(self).write(
      to: folder.appendingPathComponent(Self.fileName), options: .atomic)
  }

  /// Marks `folder` as owned by this process.
  package static func mark(_ folder: URL) throws {
    guard let current = ProcessTable.current else {
      throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: folder.path])
    }
    try Self(owner: current).write(to: folder)
  }

  /// Records the Siril `pid` working in `folder`, keeping its owner.
  package static func recordSiril(pid: Int32, in folder: URL, table: ProcessTable = .live) throws {
    guard var marker = read(folder), let siril = table.identity(pid) else { return }
    marker.siril = siril
    marker.sirilExecutable = table.executable(pid)
    try marker.write(to: folder)
  }

  /// The marker of `folder`, or `nil` when it has none (or one that does not decode).
  package static func read(_ folder: URL) -> Self? {
    let url = folder.appendingPathComponent(fileName)
    return (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
  }
}
