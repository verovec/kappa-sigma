package import Foundation

/// Removing a project's kept bucket frames (card 0192): the one deletion the cache allows, and
/// the predicate that decides it on paths alone.
extension RemoteFrameCache {
  /// The folder under the scratch folder that holds every project's kept bucket frames.
  package static let folderName = "remote-frames"

  /// A cache whose folder is not one a project's copies live in: nothing was deleted.
  package struct NotRemovable: Error, Equatable, CustomStringConvertible {
    /// The folder that was refused.
    package let path: String

    /// The refusal of `path`.
    package init(path: String) {
      self.path = path
    }

    /// One line naming the folder.
    package var description: String {
      "\(path) is not a folder of downloaded frames: nothing was deleted"
    }
  }

  /// Whether this cache's folder may be deleted: only a project's own folder, directly under
  /// `<scratch>/remote-frames`.
  ///
  /// Decided on the paths alone, symlinks and `..` resolved. Refused: the scratch folder, the
  /// folder of every project's copies, anything deeper or elsewhere, and any folder that is, holds
  /// or lies inside one of `protected` (the capture nights, the library, the project package) —
  /// a deletion never reaches a capture, whatever the settings say (R7).
  package func isRemovable(scratch: URL, protected: [URL]) -> Bool {
    let home = Self.parts(scratch.appendingPathComponent(Self.folderName, isDirectory: true))
    let own = Self.parts(root)
    guard own.count == home.count + 1, Array(own.prefix(home.count)) == home,
      let name = own.last, !name.isEmpty, name != ".", name != ".."
    else { return false }
    return !protected.contains { url in
      let other = Self.parts(url)
      return other.starts(with: own) || own.starts(with: other)
    }
  }

  /// Deletes this project's kept frames and answers the bytes freed; throws `NotRemovable`,
  /// having deleted nothing, when `isRemovable` refuses the folder.
  ///
  /// The folder goes as a whole — it was created by this app for these copies alone — and
  /// nothing outside it is walked. The buckets are never written (R7).
  @discardableResult
  package func remove(scratch: URL, protected: [URL]) throws -> Int64 {
    guard isRemovable(scratch: scratch, protected: protected) else {
      throw NotRemovable(path: root.path)
    }
    guard FileManager.default.fileExists(atPath: root.path) else { return 0 }
    let freed = size()
    try FileManager.default.removeItem(at: root)
    return freed
  }

  /// The components of `url` as the volume resolves them.
  private static func parts(_ url: URL) -> [String] {
    url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
  }
}
