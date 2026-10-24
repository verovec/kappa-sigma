internal import Foundation
internal import ProjectKit

/// The legacy walk (`filepath.WalkDir`): depth-first, entries of each folder in byte order of
/// their names, hidden folders skipped, symlinked folders not followed.
///
/// A package folder (a `.astrostack` project, an app) is never walked (card 0101): a project
/// saved among the captures holds stacks with no OBJECT, read as lights of another object.
enum InspectWalk {
  /// What a walk found: the files, and the package folders it did not enter.
  struct Listing {
    var files: [String] = []
    var packages: [String] = []
  }

  /// Every non-folder entry under `root`, in walk order, and the packages skipped. `skippingOutput`
  /// also skips any folder named `output` (case-insensitive): the legacy pipeline's own results.
  static func listing(under root: String, skippingOutput: Bool) throws -> Listing {
    var out = Listing()
    try visit(root, isRoot: true, skippingOutput: skippingOutput, into: &out)
    return out
  }

  /// Whether the folder at `path` is a package: a project by its extension (the app may not be
  /// registered with Launch Services, as under `swift test`), anything else as the Finder says.
  static func isPackage(_ path: String) -> Bool {
    let url = URL(fileURLWithPath: path, isDirectory: true)
    if url.pathExtension.lowercased() == ProjectPackage.fileExtension { return true }
    return (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) == true
  }

  /// Whether `path` is a folder (not following a symlink).
  static func isFolder(_ path: String) -> Bool {
    let type = try? FileManager.default.attributesOfItem(atPath: path)[.type] as? FileAttributeType
    return type == .typeDirectory
  }

  private static func visit(
    _ folder: String, isRoot: Bool, skippingOutput: Bool, into out: inout Listing
  ) throws {
    let name = PathMeta.baseName(folder)
    if !isRoot && (name.hasPrefix(".") || (skippingOutput && name.lowercased() == "output")) {
      return
    }
    // A root too: a project picked as a capture folder is still a project.
    if isPackage(folder) {
      out.packages.append(folder)
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
        out.files.append(path)
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
