package import Foundation

/// Removing a project's kept bucket frames (card 0192): the one deletion the cache allows, and
/// the predicate that decides it on paths alone.
extension RemoteFrameCache {
  /// The folder under the scratch folder that holds every project's kept bucket frames.
  package static let folderName = "remote-frames"

  /// Whether this cache's folder may be deleted: only a project's own folder, directly under
  /// `<scratch>/remote-frames`.
  ///
  /// Decided on the paths alone, with the rule the scratch sweep and Settings already apply
  /// (`LeftoverSweep`: links resolved, names without case). Refused: the scratch folder, the
  /// folder of every project's copies, anything deeper or elsewhere, and any folder that is, holds
  /// or lies inside one of `protected` (the capture nights, the library, the project package) —
  /// a deletion never reaches a capture, whatever the settings say (R7).
  package func isRemovable(scratch: URL, protected: [URL]) -> Bool {
    let home = scratch.appendingPathComponent(Self.folderName, isDirectory: true)
    let parent = root.standardizedFileURL.deletingLastPathComponent()
    let name = root.standardizedFileURL.lastPathComponent
    guard !name.isEmpty, name != ".", name != "..", name != "/",
      LeftoverSweep.contains(home, parent), LeftoverSweep.contains(parent, home)
    else { return false }
    return !protected.contains { LeftoverSweep.overlaps(root, $0) }
  }

  /// Deletes this project's kept frames; throws `PreprocessError.keptFramesNotRemovable`,
  /// having deleted nothing, when `isRemovable` refuses the folder.
  ///
  /// The folder goes as a whole — it was created by this app for these copies alone — and
  /// nothing outside it is walked. The buckets are never written (R7).
  package func remove(scratch: URL, protected: [URL]) throws {
    guard isRemovable(scratch: scratch, protected: protected) else {
      throw PreprocessError.keptFramesNotRemovable(path: root.path)
    }
    guard FileManager.default.fileExists(atPath: root.path) else { return }
    try FileManager.default.removeItem(at: root)
  }
}
