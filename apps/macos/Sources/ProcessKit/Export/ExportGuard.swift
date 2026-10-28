package import Foundation

/// Where an export may not write: the astro folder's read-only subfolders (rule R7).
///
/// Captures, legacy runs, the calibration library and the test fixtures. The root is the
/// caller's (Settings' astro folder, card 0148): ProcessKit knows no home.
package enum ExportGuard {
  /// The read-only folders under the astro root.
  package static let readOnly = ["captures", "runs", "library", "fixtures"]

  /// Why `folder` may not receive an export, or `nil`.
  ///
  /// Links are resolved first and names compared without case (APFS is case-insensitive), so
  /// `<astro>/Captures` or a link into the runs is refused too.
  package static func refusal(for folder: URL, astro: URL) -> String? {
    let target = resolved(folder)
    for relative in readOnly {
      let root = resolved(astro.appendingPathComponent(relative))
      if target.starts(with: root) {
        return "\(folder.path) is inside \(astro.path)/\(relative), which the app never writes: "
          + "choose a folder outside it"
      }
    }
    return nil
  }

  /// The lowercased path components of `url` with every link resolved: Foundation resolves links
  /// only in a path that exists, so the nearest existing ancestor is resolved and the rest
  /// appended.
  static func resolved(_ url: URL) -> [String] {
    var existing = url.standardizedFileURL
    var rest: [String] = []
    while !FileManager.default.fileExists(atPath: existing.path), existing.pathComponents.count > 1
    {
      rest.insert(existing.lastPathComponent, at: 0)
      existing.deleteLastPathComponent()
    }
    return (existing.resolvingSymlinksInPath().pathComponents + rest).map { $0.lowercased() }
  }
}
