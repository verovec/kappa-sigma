package import Foundation

/// The capture folders one panel returned, as one import scans them (card 0174).
///
/// The scan never de-duplicates overlapping roots, so `M31/` with `M31/2026-10-18/` would list that
/// night twice: the folder inside another chosen one is dropped here, and said so (R2: the sheet
/// shows it, never silently). Folders are compared standardised; each one keeps the spelling it
/// was chosen with, so a single-folder import is the request it always was.
package struct ImportFolders: Sendable {
  /// A chosen folder another chosen folder already covers.
  package struct Nested: Hashable, Sendable {
    /// The folder as it was chosen.
    package var path: String
    /// The kept folder it lies in.
    package var ancestor: String

    /// `path` dropped because it lies in `ancestor`.
    package init(path: String, ancestor: String) {
      self.path = path
      self.ancestor = ancestor
    }
  }

  /// The folders to scan, sorted by standardised path; the first is the primary one.
  package private(set) var paths: [String] = []
  /// The folders dropped because a kept one contains them, in the same order.
  package private(set) var dropped: [Nested] = []

  /// The folders of `urls`, in any order, duplicates removed and nested folders dropped.
  package init(_ urls: [URL]) {
    let chosen = urls.map { (key: $0.standardizedFileURL.path, path: $0.path) }
      .sorted { ($0.key, $0.path) < ($1.key, $1.path) }
    var kept: [(key: String, path: String)] = []
    var seen = Set<String>()
    for folder in chosen where seen.insert(folder.key).inserted {
      if let ancestor = kept.first(where: { Self.contains($0.key, folder.key) }) {
        dropped.append(Nested(path: folder.path, ancestor: ancestor.path))
      } else {
        kept.append(folder)
      }
    }
    paths = kept.map(\.path)
  }

  /// Whether standardised folder `child` lies strictly inside `parent` (`M31-DB` is not in `M31`).
  private static func contains(_ parent: String, _ child: String) -> Bool {
    child.hasPrefix(parent.hasSuffix("/") ? parent : parent + "/")
  }
}

extension ImportRequest {
  /// The folders a multi-selection panel returned, as one import scans them.
  package static func folders(_ urls: [URL]) -> ImportFolders {
    ImportFolders(urls)
  }
}
