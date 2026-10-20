internal import Foundation

/// The legacy walk (`filepath.WalkDir`): depth-first, entries of each folder in byte order of
/// their names, hidden folders skipped, symlinked folders not followed.
enum InspectWalk {
  /// Every non-folder entry under `root`, in walk order. `skippingOutput` also skips any folder
  /// named `output` (case-insensitive): the legacy pipeline's own results.
  static func files(under root: String, skippingOutput: Bool) throws -> [String] {
    var out: [String] = []
    try visit(root, isRoot: true, skippingOutput: skippingOutput, into: &out)
    return out
  }

  /// Whether `path` is a folder (not following a symlink).
  static func isFolder(_ path: String) -> Bool {
    let type = try? FileManager.default.attributesOfItem(atPath: path)[.type] as? FileAttributeType
    return type == .typeDirectory
  }

  private static func visit(
    _ folder: String, isRoot: Bool, skippingOutput: Bool, into out: inout [String]
  ) throws {
    let name = PathMeta.baseName(folder)
    if !isRoot && (name.hasPrefix(".") || (skippingOutput && name.lowercased() == "output")) {
      return
    }
    // An unlistable folder fails the scan, as Go's WalkDir did: an empty capture would hide a
    // wrong path or a missing Full Disk Access.
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder) else {
      throw InspectError.unreadableFolder(folder)
    }
    for entry in names.sorted(by: { $0.utf8.lexicographicallyPrecedes($1.utf8) }) {
      let path = folder.hasSuffix("/") ? folder + entry : folder + "/" + entry
      if isFolder(path) {
        try visit(path, isRoot: false, skippingOutput: skippingOutput, into: &out)
      } else {
        out.append(path)
      }
    }
  }

  /// The folder holding `path` (`filepath.Dir`).
  static func parent(_ path: String) -> String {
    guard let slash = path.lastIndex(of: "/") else { return "." }
    return slash == path.startIndex ? "/" : String(path[..<slash])
  }

  /// `path` relative to `root` when it lies beneath it, else `path` unchanged.
  static func relative(_ path: String, to root: String) -> String {
    let prefix = root.hasSuffix("/") ? root : root + "/"
    return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
  }
}
