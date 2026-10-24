package import Foundation
internal import OSLog

/// Removes what a dead run, Siril session, untitled project or test left in the scratch folders.
///
/// Each root names a folder and the prefix of the entries it may take (`run_`, `siril-`…). Only
/// a folder with a marker (`ScratchOwner`) is ever taken, once its owner no longer runs and after
/// its recorded Siril is stopped (only while that pid still runs the `siril-cli` started when
/// recorded; a Siril that keeps running keeps its folder). An entry without a marker, a file or
/// a symbolic link is never touched, whatever its age: nothing proves the app made it. A root
/// that is `/`, inside or around the astro data folder (captures, library, runs: read-only, R7)
/// is refused whatever the caller passed.
package struct LeftoverSweep: Sendable {
  /// A folder whose entries starting with `prefix` the sweep may take (`""`: every entry).
  package struct Root: Sendable {
    /// The folder whose entries are swept (never the folder itself).
    package var folder: URL
    /// The start of the entry names the sweep may take.
    package var prefix: String

    /// A root from its parts.
    package init(folder: URL, prefix: String) {
      self.folder = folder
      self.prefix = prefix
    }
  }

  /// One folder removed, and the bytes it held.
  package struct Removal: Equatable, Sendable {
    /// The folder or file removed.
    package var path: URL
    /// The bytes it took on disk.
    package var bytes: Int64
  }

  /// The astro data folder (`~/Documents/astro`): never swept.
  package static let dataFolder = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Documents/astro", isDirectory: true)

  /// The folders swept.
  package var roots: [Root]
  /// Who runs: the host's processes, or a test's table.
  package var table: ProcessTable
  /// Folders no root may be inside or around.
  package var protected: [URL]

  /// A sweep of `roots`, asking `table` who runs.
  package init(roots: [Root], table: ProcessTable = .live, protected: [URL] = [Self.dataFolder]) {
    self.roots = roots
    self.table = table
    self.protected = protected
  }

  /// The app's scratch roots under `temporary`: Siril's FIFO folders, the runs' work folders
  /// under `work` (`AstroStack/Work` unless the user chose another), the untitled projects.
  package static func appRoots(
    temporary: URL = FileManager.default.temporaryDirectory, work: URL? = nil
  ) -> [Root] {
    let app = temporary.appendingPathComponent("AstroStack", isDirectory: true)
    return [
      Root(folder: app, prefix: "siril-"),
      Root(folder: work ?? app.appendingPathComponent("Work", isDirectory: true), prefix: "run_"),
      Root(folder: app.appendingPathComponent("Untitled", isDirectory: true), prefix: ""),
    ]
  }

  /// Sweeps every root; returns what it removed, each removal logged.
  @discardableResult
  package func run() -> [Removal] {
    roots.filter(allows).flatMap(sweep)
  }

  private func sweep(_ root: Root) -> [Removal] {
    let manager = FileManager.default
    let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
    let entries =
      (try? manager.contentsOfDirectory(at: root.folder, includingPropertiesForKeys: keys)) ?? []
    var removed: [Removal] = []
    for entry in entries where entry.lastPathComponent.hasPrefix(root.prefix) {
      guard let values = try? entry.resourceValues(forKeys: Set(keys)),
        values.isDirectory == true, values.isSymbolicLink != true,
        let marker = ScratchOwner.read(entry), !marker.isAlive(in: table)
      else { continue }
      // A Siril that keeps running keeps its folder: removed, nothing would point to it any more.
      if let siril = marker.siril, !stop(siril) {
        Self.logger.error("kept \(entry.path): its Siril \(siril.pid) still runs")
        continue
      }
      let bytes = Self.allocatedBytes(entry)
      do {
        try manager.removeItem(at: entry)
        Self.logger.notice("removed leftover \(entry.path) (\(bytes) bytes)")
        removed.append(Removal(path: entry, bytes: bytes))
      } catch {
        Self.logger.error("could not remove leftover \(entry.path): \(error)")
      }
    }
    return removed
  }

  /// Stops the recorded Siril, only while its pid still runs the `siril-cli` recorded; true
  /// once it no longer runs.
  private func stop(_ siril: ProcessIdentity) -> Bool {
    guard table.identity(siril.pid) == siril else { return true }
    guard let path = table.executable(siril.pid),
      URL(fileURLWithPath: path).lastPathComponent == "siril-cli"
    else { return false }
    Self.logger.notice("stopping orphan siril-cli \(siril.pid)")
    table.terminate(siril.pid)
    return table.identity(siril.pid) != siril
  }

  /// True when the sweep may look into `root`: not `/`, neither inside nor around a protected
  /// folder.
  package func allows(_ root: Root) -> Bool {
    let path = Self.canonical(root.folder)
    let refused =
      path == "/"
      || protected.map(Self.canonical).contains { folder in
        path == folder || path.hasPrefix(folder + "/") || folder.hasPrefix(path + "/")
      }
    if refused { Self.logger.error("refused to sweep \(root.folder.path): not a scratch folder") }
    return !refused
  }

  private static func canonical(_ url: URL) -> String {
    let path = url.standardizedFileURL.resolvingSymlinksInPath().path
    return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
  }

  /// The bytes the files under `folder` take on disk.
  package static func allocatedBytes(_ folder: URL) -> Int64 {
    let key = URLResourceKey.totalFileAllocatedSizeKey
    guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [key])
    else { return 0 }
    var total: Int64 = 0
    for case let file as URL in files {
      total += Int64((try? file.resourceValues(forKeys: [key]).totalFileAllocatedSize) ?? 0)
    }
    return total
  }

  private static let logger = Logger(subsystem: "fr.astrostack", category: "StackKit/sweep")
}
