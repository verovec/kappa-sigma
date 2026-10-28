package import Foundation

/// The astro folder Settings chose (card 0148): the read-only data root (R7).
///
/// Captures, legacy runs, the calibration library and the fixtures — `~/Documents/astro` unless
/// chosen, kept as a path in the app's defaults. Every site that named the root by hand reads
/// this instead.
///
/// The app never writes under it; a root the app does write under (the scratch folder,
/// `~/AstroStack`) is refused. Nothing else is judged: an astro folder without `captures/` is a
/// fresh disk, and Settings only *shows* which subfolders exist (R2).
package nonisolated struct AstroFolderSetting {
  /// The subfolders the root is made of, in the order Settings lists them.
  package static let subfolders = ["captures", "runs", "library", "fixtures"]
  /// What Settings reports on: the four subfolders and the star catalogues of the plate solve.
  package static let shown = subfolders + ["library/catalogues"]

  /// The root when nothing is chosen: `~/Documents/astro`.
  package static var defaultFolder: URL {
    URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(
      "Documents/astro", isDirectory: true)
  }

  private static let key = "astroFolder"
  private let defaults: UserDefaults
  private let home: URL
  /// Where the app itself writes: never the read-only root.
  private let appOwned: [URL]

  /// The setting stored in `defaults`; `home` and `scratch` locate what the app writes under.
  package init(
    defaults: UserDefaults = .standard, home: URL = URL(fileURLWithPath: NSHomeDirectory()),
    scratch: URL = ScratchSetting().folder
  ) {
    self.defaults = defaults
    self.home = home
    appOwned = [home.appendingPathComponent("AstroStack", isDirectory: true), scratch]
  }

  /// The folder the user chose, `nil` for the default.
  package var chosen: URL? {
    defaults.string(forKey: Self.key).map { URL(fileURLWithPath: $0, isDirectory: true) }
  }

  /// The root now: the chosen folder, else `~/Documents/astro` under `home`.
  package var folder: URL {
    chosen ?? home.appendingPathComponent("Documents/astro", isDirectory: true)
  }

  /// The captures, by target then night (read-only).
  package var captures: URL { folder.appendingPathComponent("captures", isDirectory: true) }
  /// The legacy runs (read-only).
  package var runs: URL { folder.appendingPathComponent("runs", isDirectory: true) }
  /// The calibration library (read-only).
  package var library: URL { folder.appendingPathComponent("library", isDirectory: true) }
  /// The test fixtures (read-only).
  package var fixtures: URL { folder.appendingPathComponent("fixtures", isDirectory: true) }
  /// The local star catalogues (`library/catalogues`), for the plate solve and SPCC.
  package var catalogues: URL { library.appendingPathComponent("catalogues", isDirectory: true) }

  /// Whether the subfolder `name` exists under the root: shown by Settings, decided by nobody.
  package func has(_ name: String) -> Bool {
    (try? folder.appendingPathComponent(name).resourceValues(forKeys: [.isDirectoryKey]))?
      .isDirectory == true
  }

  /// Chooses `folder` (`nil` = back to the default); false, nothing stored, for a path that is
  /// not an existing folder or one under what the app writes (the scratch folder, `~/AstroStack`).
  @discardableResult
  package func choose(_ folder: URL?) -> Bool {
    guard let folder else {
      defaults.removeObject(forKey: Self.key)
      return true
    }
    guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
      return false
    }
    let target = Self.resolved(folder)
    guard !appOwned.contains(where: { target.starts(with: Self.resolved($0)) }) else {
      return false
    }
    defaults.set(folder.standardizedFileURL.path, forKey: Self.key)
    return true
  }

  /// The path components of `url`, links resolved, case folded (APFS is case-insensitive).
  private static func resolved(_ url: URL) -> [String] {
    url.resolvingSymlinksInPath().standardizedFileURL.pathComponents.map { $0.lowercased() }
  }
}
