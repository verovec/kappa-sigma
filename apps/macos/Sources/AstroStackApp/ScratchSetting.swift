package import Foundation

/// The scratch folder Settings chose for preprocessing runs (card 0098), kept as a path in the
/// app's defaults.
///
/// Runs never write into the chosen folder itself but into its `AstroStack/Work` subfolder, which
/// the app owns: the leftover sweep (card 0113) removes only what is under it, never the user's
/// own files beside it.
package nonisolated struct ScratchSetting {
  /// Where runs work when nothing is chosen: the user's temporary folder, on the system volume.
  package static var defaultFolder: URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(work, isDirectory: true)
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

  /// Chooses `folder` (`nil` = back to the default); false, nothing stored, for a folder inside
  /// — or around — the astro folder (R7: the app never writes under the data root, and the
  /// leftover sweep would refuse such a work folder as protected and never clean it).
  @discardableResult
  package func choose(_ folder: URL?) -> Bool {
    guard let folder else {
      defaults.removeObject(forKey: Self.key)
      return true
    }
    // The scratch folder is what the astro setting refuses, never the reverse: no recursion.
    let root = astro ?? AstroFolderSetting(defaults: defaults, scratch: self.folder).folder
    guard !AstroFolderSetting.overlap(folder, root) else { return false }
    defaults.set(folder.standardizedFileURL.path, forKey: Self.key)
    return true
  }
}
