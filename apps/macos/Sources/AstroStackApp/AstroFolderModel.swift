package import Foundation
internal import Observation

/// Settings › Astro folder as the window shows it (card 0148): the root, which of its subfolders
/// exist, and whether the last pick was refused.
///
/// The view reads it; tests drive it. Nothing here decides anything from the subfolders found
/// (R2): they are shown, that is all.
@Observable
package final class AstroFolderModel {
  /// The root now.
  package private(set) var folder: URL
  /// The last folder picked was no folder, or one the app writes under; the root was kept.
  package private(set) var refused = false
  /// Which subfolders the root holds, read by `refresh` off the main thread, never on render.
  package private(set) var lines: [(name: String, found: Bool)] = []
  private let setting: AstroFolderSetting

  /// The model over `setting`, starting on its root.
  package init(setting: AstroFolderSetting = AstroFolderSetting()) {
    self.setting = setting
    folder = setting.folder
  }

  /// Whether a folder was chosen (Default has something to undo).
  package var chosen: Bool { setting.chosen != nil }

  /// The root as shown: `~` for the home folder.
  package var path: String { (folder.path as NSString).abbreviatingWithTildeInPath }

  /// Chooses `url` (`nil` = back to the default); a refused pick keeps the root and says so.
  package func pick(_ url: URL?) {
    refused = !setting.choose(url)
    folder = setting.folder
  }

  /// Reads which subfolders the root holds, off the main thread: an unmounted or slow volume
  /// never blocks the window.
  package func refresh() async {
    lines = await Self.lines(under: folder)
  }

  /// The subfolders of `root` and whether each exists.
  @concurrent package nonisolated static func lines(
    under root: URL
  ) async -> [(name: String, found: Bool)] {
    AstroFolderSetting.shown.map {
      ($0, AstroFolderSetting.isFolder(root.appendingPathComponent($0, isDirectory: true)))
    }
  }
}
