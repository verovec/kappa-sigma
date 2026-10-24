package import Foundation
internal import ProcessKit

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
  private let home: URL

  /// The setting stored in `defaults`; `home` locates the read-only sources (R7).
  package init(
    defaults: UserDefaults = .standard, home: URL = URL(fileURLWithPath: NSHomeDirectory())
  ) {
    self.defaults = defaults
    self.home = home
  }

  /// The folder the user chose, `nil` for the default.
  package var chosen: URL? {
    defaults.string(forKey: Self.key).map { URL(fileURLWithPath: $0, isDirectory: true) }
  }

  /// The folder runs go to now: the chosen folder's `AstroStack/Work`, else the default.
  package var folder: URL {
    chosen?.appendingPathComponent(Self.work, isDirectory: true) ?? Self.defaultFolder
  }

  /// Chooses `folder` (`nil` = back to the default); false, nothing stored, for a folder under
  /// the read-only sources (R7: the guard exports use).
  @discardableResult
  package func choose(_ folder: URL?) -> Bool {
    guard let folder else {
      defaults.removeObject(forKey: Self.key)
      return true
    }
    guard ExportGuard.refusal(for: folder, home: home) == nil else { return false }
    defaults.set(folder.standardizedFileURL.path, forKey: Self.key)
    return true
  }
}
