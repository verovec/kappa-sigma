package import Foundation

/// Where an export may not write: the captures and the legacy runs are read-only (rule R7).
package enum ExportGuard {
  /// The read-only folders under the user's home.
  static let readOnly = ["Documents/astro/captures", "Documents/astro/runs"]

  /// Why `folder` may not receive an export, or `nil`: links are resolved first, so a path that
  /// reaches a read-only folder through a symlink is refused too.
  package static func refusal(for folder: URL, home: URL) -> String? {
    let target = resolved(folder)
    for relative in readOnly {
      let root = resolved(home.appendingPathComponent(relative))
      if target.starts(with: root) {
        return "\(folder.path) is inside ~/\(relative), which the app never writes: "
          + "choose a folder outside it"
      }
    }
    return nil
  }

  /// The path components of `url` with every link resolved: Foundation resolves links only in a
  /// path that exists, so the nearest existing ancestor is resolved and the rest appended.
  static func resolved(_ url: URL) -> [String] {
    var existing = url.standardizedFileURL
    var rest: [String] = []
    while !FileManager.default.fileExists(atPath: existing.path), existing.pathComponents.count > 1
    {
      rest.insert(existing.lastPathComponent, at: 0)
      existing.deleteLastPathComponent()
    }
    return existing.resolvingSymlinksInPath().pathComponents + rest
  }
}
