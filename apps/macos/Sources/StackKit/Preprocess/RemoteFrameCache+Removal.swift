package import Foundation
internal import OSLog

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
    // The path judged is the path deleted: one that spells `..` or `.` is refused, since the
    // volume would resolve it through links the rule below never saw.
    let judged = root.standardizedFileURL
    guard judged.path == root.path else { return false }
    let parent = judged.deletingLastPathComponent()
    let name = judged.lastPathComponent
    guard !name.isEmpty, name != "/", LeftoverSweep.contains(home, parent),
      LeftoverSweep.contains(parent, home),
      // A link in the project's place would hand the deletion another folder.
      (try? root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true
    else { return false }
    return !protected.contains { LeftoverSweep.overlaps(root, $0) }
  }

  /// Deletes this project's kept frames; throws `PreprocessError.keptFramesNotRemovable`,
  /// having deleted nothing, when `isRemovable` refuses the folder.
  ///
  /// The folder goes as a whole — it was created by this app for these copies alone — and
  /// nothing outside it is walked. The buckets are never written (R7). Each removal, refusal
  /// and failure is logged with its folder, as the scratch sweep logs its own.
  package func remove(scratch: URL, protected: [URL]) throws {
    guard isRemovable(scratch: scratch, protected: protected) else {
      Self.logger.error("refused to remove \(root.path, privacy: .public): not a project's copies")
      throw PreprocessError.keptFramesNotRemovable(path: root.path)
    }
    guard FileManager.default.fileExists(atPath: root.path) else { return }
    do {
      try FileManager.default.removeItem(at: root)
      Self.logger.notice("removed the downloaded frames in \(root.path, privacy: .public)")
    } catch {
      Self.logger.error("could not remove \(root.path, privacy: .public): \(error)")
      throw error
    }
  }

  private static let logger = Logger(subsystem: "fr.astrostack", category: "StackKit/kept-frames")
}
