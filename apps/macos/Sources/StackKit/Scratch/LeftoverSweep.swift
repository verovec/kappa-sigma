package import Foundation
internal import OSLog

/// Removes what a dead run, Siril session, untitled project or test left in the scratch folders.
///
/// Each root names a folder and the prefix of the entries it may take (`run_`, `siril-`…). An
/// entry with a marker (`ScratchOwner`) goes once its owner no longer runs, after its recorded
/// Siril is stopped (only when that pid still runs a `siril-cli` started when recorded); an
/// entry without one goes once untouched for `unmarkedAge` (a day). A root inside or around the
/// astro data folder (captures, library, runs: read-only, R7) is refused whatever the caller
/// passed.
package struct LeftoverSweep: Sendable {
  /// A folder whose entries starting with `prefix` the sweep may take (`""`: every entry).
  package struct Root: Sendable {
    package var folder: URL
    package var prefix: String

    /// A root from its parts.
    package init(folder: URL, prefix: String) {
      self.folder = folder
      self.prefix = prefix
    }
  }

  /// One folder removed, and the bytes it held.
  package struct Removal: Equatable, Sendable {
    package var path: URL
    package var bytes: Int64
  }

  /// An unmarked entry untouched this long belongs to no running process.
  package static let staleAge: TimeInterval = 24 * 3600

  /// The astro data folder (`~/Documents/astro`): never swept.
  package static let dataFolder = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Documents/astro", isDirectory: true)

  package var roots: [Root]
  package var table: ProcessTable
  package var now: Date
  package var protected: [URL]
  /// How long an unmarked entry stays untouched before it goes.
  package var unmarkedAge: TimeInterval

  /// A sweep of `roots`, asking `table` who runs, at `now`.
  package init(
    roots: [Root], table: ProcessTable = .live, now: Date = Date(),
    protected: [URL] = [Self.dataFolder], unmarkedAge: TimeInterval = Self.staleAge
  ) {
    self.roots = roots
    self.table = table
    self.now = now
    self.protected = protected
    self.unmarkedAge = unmarkedAge
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
    roots.filter(isAllowed).flatMap(sweep)
  }

  private func sweep(_ root: Root) -> [Removal] {
    let manager = FileManager.default
    let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]
    let entries =
      (try? manager.contentsOfDirectory(at: root.folder, includingPropertiesForKeys: keys)) ?? []
    var removed: [Removal] = []
    for entry in entries where entry.lastPathComponent.hasPrefix(root.prefix) {
      guard let values = try? entry.resourceValues(forKeys: Set(keys)),
        values.isDirectory == true, values.isSymbolicLink != true, isLeftover(entry, values)
      else { continue }
      if let siril = ScratchOwner.read(entry)?.siril { stop(siril) }
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

  /// True when `entry` is left over.
  ///
  /// Marked: its owner no longer runs. Unmarked: untouched for `unmarkedAge`.
  private func isLeftover(_ entry: URL, _ values: URLResourceValues) -> Bool {
    if let marker = ScratchOwner.read(entry) { return !marker.isAlive(in: table) }
    guard let modified = values.contentModificationDate else { return false }
    return now.timeIntervalSince(modified) > unmarkedAge
  }

  /// Stops the recorded Siril, only while its pid still runs the `siril-cli` recorded.
  private func stop(_ siril: ProcessIdentity) {
    guard table.identity(siril.pid) == siril,
      let path = table.executable(siril.pid),
      URL(fileURLWithPath: path).lastPathComponent == "siril-cli"
    else { return }
    Self.logger.notice("stopping orphan siril-cli \(siril.pid)")
    table.terminate(siril.pid)
  }

  /// Neither inside nor around a protected folder.
  private func isAllowed(_ root: Root) -> Bool {
    let path = Self.canonical(root.folder)
    for folder in protected.map(Self.canonical)
    where path == folder || path.hasPrefix(folder + "/") || folder.hasPrefix(path + "/") {
      Self.logger.error("refused to sweep \(root.folder.path): the astro data stays read-only")
      return false
    }
    return true
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
