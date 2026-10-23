package import Foundation

/// The room left where a run's scratch goes (card 0098).
package enum ScratchSpace {
  /// Where macOS mounts every disk but the startup one.
  private static let volumes = "/Volumes"

  /// Bytes the volume of `folder` can still give an important write (purgeable space counted,
  /// as the system frees it for one), read on its nearest existing ancestor: the run creates the
  /// folder itself. `nil` when the volume does not say, or when the folder's own disk is not
  /// mounted (climbing to `/Volumes` would read the startup disk's room instead).
  package static func available(at folder: URL) -> Int64? {
    var url = folder.standardizedFileURL
    while !FileManager.default.fileExists(atPath: url.path) {
      let parent = url.deletingLastPathComponent()
      guard parent != url, parent.path != volumes else { return nil }
      url = parent
    }
    let key = URLResourceKey.volumeAvailableCapacityForImportantUsageKey
    return (try? url.resourceValues(forKeys: [key]))?.volumeAvailableCapacityForImportantUsage
  }
}
