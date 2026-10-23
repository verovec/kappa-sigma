package import Foundation
internal import OSLog

/// A folder under a project's `stacks/` that no stack records, and the bytes it holds.
package struct LeftoverStack: Equatable, Hashable, Sendable {
  /// Its path in the package (`stacks/<run id>`), as a stack's `bundlePath` reads.
  package var path: String
  /// The bytes its files take on disk.
  package var bytes: Int64

  /// A leftover from its parts.
  package init(path: String, bytes: Int64) {
    self.path = path
    self.bytes = bytes
  }
}

/// What a failed, cancelled or unregistered run leaves in a project's `stacks/`.
///
/// Finished masters are kept by design (Preprocess/README.md): a folder holding one is never
/// removed in silence, it is listed for the user to delete (R2). Only a folder with nothing
/// finished in it goes on its own, and every removal is logged.
package enum StackLeftovers {
  /// A removal refused: the path is not a stack folder of the package.
  package struct Refusal: Error, Equatable {
    /// The path refused.
    package var path: String
  }

  /// True when `folder` holds a finished master (`master_<tag>.fits`).
  package static func holdsMaster(_ folder: URL) -> Bool {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    return names.contains { $0.hasPrefix("master_") && $0.hasSuffix(".fits") }
  }

  /// Removes the folder of a run that did not finish unless it holds a finished master.
  ///
  /// A cancelled run's stream ends before its task does: Siril may still be saving a master
  /// there. The folder is judged only once no run holds it (`TargetLock`); one still held after
  /// `wait` (another run's, or a teardown that hangs) is kept, and listed at the next open.
  @discardableResult
  package static func removeUnfinished(_ folder: URL, wait: Duration = .seconds(10)) async
    -> LeftoverSweep.Removal?
  {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: wait)
    while TargetLock.isHeld(folder) {
      guard clock.now < deadline, (try? await Task.sleep(for: .milliseconds(50))) != nil else {
        logger.notice("kept \(folder.path): a run still holds it")
        return nil
      }
    }
    guard FileManager.default.fileExists(atPath: folder.path), !holdsMaster(folder) else {
      return nil
    }
    return remove(folder)
  }

  /// The stack folders of `package` that no path in `recorded` names, oldest first: an empty one
  /// is removed, one holding files is returned for the user to keep or delete.
  package static func orphans(in package: URL, recorded: Set<String>) -> [LeftoverStack] {
    let stacks = package.appendingPathComponent("stacks", isDirectory: true)
    let names = (try? FileManager.default.contentsOfDirectory(atPath: stacks.path)) ?? []
    var listed: [LeftoverStack] = []
    for name in names.sorted() where !recorded.contains("stacks/\(name)") {
      let folder = stacks.appendingPathComponent(name, isDirectory: true)
      var isFolder: ObjCBool = false
      guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isFolder),
        isFolder.boolValue
      else { continue }
      if holdsFiles(folder) {
        listed.append(
          LeftoverStack(path: "stacks/\(name)", bytes: LeftoverSweep.allocatedBytes(folder)))
      } else {
        remove(folder)
      }
    }
    return listed
  }

  /// Deletes `leftover` from `package`; only a folder directly under its `stacks/`.
  package static func remove(_ leftover: LeftoverStack, in package: URL) throws {
    let parts = leftover.path.split(separator: "/", omittingEmptySubsequences: false)
    guard parts.count == 2, parts[0] == "stacks", !["", ".", ".."].contains(parts[1]) else {
      throw Refusal(path: leftover.path)
    }
    let folder = package.appendingPathComponent(leftover.path, isDirectory: true)
    try FileManager.default.removeItem(at: folder)
    logger.notice("removed stack folder \(folder.path) (\(leftover.bytes) bytes)")
  }

  @discardableResult
  private static func remove(_ folder: URL) -> LeftoverSweep.Removal? {
    let bytes = LeftoverSweep.allocatedBytes(folder)
    do {
      try FileManager.default.removeItem(at: folder)
    } catch {
      logger.error("could not remove stack folder \(folder.path): \(error)")
      return nil
    }
    logger.notice("removed stack folder \(folder.path) (\(bytes) bytes)")
    return LeftoverSweep.Removal(path: folder, bytes: bytes)
  }

  /// Any regular file, at any depth.
  private static func holdsFiles(_ folder: URL) -> Bool {
    let key = URLResourceKey.isRegularFileKey
    guard
      let entries = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [key])
    else { return false }
    for case let entry as URL in entries
    where (try? entry.resourceValues(forKeys: [key]).isRegularFile) == true {
      return true
    }
    return false
  }

  private static let logger = Logger(subsystem: "fr.astrostack", category: "StackKit/stackfolders")
}
