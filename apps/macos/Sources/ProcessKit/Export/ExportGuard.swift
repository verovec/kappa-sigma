package import Foundation

/// Where an export may not write: everything the app reads from `~/Documents/astro` is
/// read-only (rule R7) — captures, legacy runs, the calibration library and the test fixtures.
package enum ExportGuard {
  /// The read-only folders under the user's home.
  static let readOnly = [
    "Documents/astro/captures", "Documents/astro/runs", "Documents/astro/library",
    "Documents/astro/fixtures",
  ]

  /// Why `folder` may not receive an export, or `nil`.
  ///
  /// Links are resolved first and names compared without case (APFS is case-insensitive), so
  /// `~/Documents/Astro/Captures` or a link into the runs is refused too.
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
