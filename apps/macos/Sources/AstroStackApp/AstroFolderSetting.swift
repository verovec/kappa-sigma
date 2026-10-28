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
    defaultFolder(under: URL(fileURLWithPath: NSHomeDirectory()))
  }

  /// The default root under `home`: its `Documents/astro`.
  package static func defaultFolder(under home: URL) -> URL {
    home.appendingPathComponent("Documents/astro", isDirectory: true)
  }

  private static let key = "astroFolder"
  private let defaults: UserDefaults
  private let home: URL
  private let scratch: URL?

  /// The setting stored in `defaults`; `home` and `scratch` locate what the app writes under —
  /// the scratch folder of the same defaults when `nil`.
  package init(
    defaults: UserDefaults = .standard, home: URL = URL(fileURLWithPath: NSHomeDirectory()),
    scratch: URL? = nil
  ) {
    self.defaults = defaults
    self.home = home
    self.scratch = scratch
  }

  /// Where the app itself writes: never the read-only root.
  ///
  /// Read by `choose` only: the readers of the root never touch the scratch setting.
  private var appOwned: [URL] {
    [
      home.appendingPathComponent("AstroStack", isDirectory: true),
      scratch ?? ScratchSetting(defaults: defaults).folder,
    ]
  }

  /// The folder the user chose, `nil` for the default.
  package var chosen: URL? {
    defaults.string(forKey: Self.key).map { URL(fileURLWithPath: $0, isDirectory: true) }
  }

  /// The root now: the chosen folder, else `~/Documents/astro` under `home`.
  package var folder: URL { chosen ?? Self.defaultFolder(under: home) }

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
    Self.isFolder(folder.appendingPathComponent(name))
  }

  /// Whether `url` is an existing folder, a symbolic link to one included.
  package static func isFolder(_ url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
      && isDirectory.boolValue
  }

  /// Whether one of the folders lies inside — or is — the other, links resolved, case folded
  /// (APFS is case-insensitive): the rule the leftover sweep applies to its roots.
  package static func overlap(_ lhs: URL, _ rhs: URL) -> Bool {
    let left = resolved(lhs)
    let right = resolved(rhs)
    return left.starts(with: right) || right.starts(with: left)
  }

  /// Chooses `folder` (`nil` = back to the default); false, nothing stored, for a path that is
  /// not an existing folder, or one under — or around — what the app writes (the scratch folder,
  /// `~/AstroStack`): the same rule as the leftover sweep, which refuses a root inside or around a
  /// protected folder, so an accepted root never silences the sweep.
  @discardableResult
  package func choose(_ folder: URL?) -> Bool {
    guard let folder else {
      defaults.removeObject(forKey: Self.key)
      return true
    }
    guard Self.isFolder(folder), !appOwned.contains(where: { Self.overlap(folder, $0) }) else {
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
