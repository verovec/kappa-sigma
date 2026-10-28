package import Foundation
internal import StackKit

/// The scratch folder Settings chose for preprocessing runs (card 0098), kept as a path in the
/// app's defaults.
///
/// Runs never write into the chosen folder itself but into its `AstroStack/Work` subfolder, which
/// the app owns: the leftover sweep (card 0113) removes only what is under it, never the user's
/// own files beside it.
package nonisolated struct ScratchSetting {
  /// Where runs work when nothing is chosen: the user's temporary folder, on the system volume.
  package static var defaultFolder: URL {
    defaultFolder(under: FileManager.default.temporaryDirectory)
  }

  /// Where runs work when nothing is chosen, under `temporary`.
  package static func defaultFolder(under temporary: URL) -> URL {
    temporary.appendingPathComponent(work, isDirectory: true)
  }

  private static let work = "AstroStack/Work"
  private static let key = "scratchFolder"
  private let defaults: UserDefaults
  private let astro: URL?

  /// The setting stored in `defaults`; `astro` is the read-only root (R7), Settings' astro folder
  /// read from the same defaults when `nil`.
  package init(defaults: UserDefaults = .standard, astro: URL? = nil) {
    self.defaults = defaults
    self.astro = astro
  }

  /// The folder the user chose, `nil` for the default.
  package var chosen: URL? {
    defaults.string(forKey: Self.key).map { URL(fileURLWithPath: $0, isDirectory: true) }
  }

  /// The folder runs go to now: the chosen folder's `AstroStack/Work`, else the default.
  package var folder: URL {
    chosen?.appendingPathComponent(Self.work, isDirectory: true) ?? Self.defaultFolder
  }

  /// Chooses `folder` (`nil` = back to the default); false, nothing stored, for a work folder
  /// inside the astro folder.
  ///
  /// The work folder is `<folder>/AstroStack/Work`: the app never writes under the data root (R7),
  /// and the sweep would refuse that work folder and never clean it — so the folders judged are
  /// the sweep's protected ones, the default data folder included whatever root was chosen. The
  /// root's parents are fine: `~/Documents` works in `~/Documents/AstroStack/Work`.
  @discardableResult
  package func choose(_ folder: URL?) -> Bool {
    guard let folder else {
      defaults.removeObject(forKey: Self.key)
      return true
    }
    // Reading the astro root never reads the scratch setting back: no recursion.
    let root = astro ?? AstroFolderSetting(defaults: defaults).folder
    let work = folder.appendingPathComponent(Self.work, isDirectory: true)
    let protected = AppDelegate.protectedFolders(root: root)
    guard !protected.contains(where: { LeftoverSweep.overlaps(work, $0) }) else { return false }
    defaults.set(folder.standardizedFileURL.path, forKey: Self.key)
    return true
  }
}
