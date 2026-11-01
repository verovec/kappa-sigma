internal import ProjectKit

// MARK: - The walk of a key space (card 0167: an S3 prefix)

extension InspectWalk {
  /// The walk of object `keys` (relative to `root`, `/`-separated), as the local walk lists it.
  ///
  /// The same tree under `root`: entries of each virtual folder in byte order of their names,
  /// hidden folders and (`skippingOutput`) `output` folders skipped, a package folder listed as
  /// skipped and not entered. A key ending in `/` (a folder marker) is no file.
  package static func listing(keys: [String], under root: String, skippingOutput: Bool) -> Listing {
    let tree = Node()
    for key in keys where !key.isEmpty && !key.hasSuffix("/") {
      var node = tree
      let parts = key.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
      for part in parts.dropLast() { node = node.child(part) }
      if let last = parts.last { node.child(last).isFile = true }
    }
    var out = Listing()
    visit(tree, at: root, isRoot: true, skippingOutput: skippingOutput, into: &out)
    return out
  }

  /// A virtual folder (or file) of the key space.
  private final class Node {
    var children: [String: Node] = [:]
    var isFile = false

    func child(_ name: String) -> Node {
      if let node = children[name] { return node }
      let node = Node()
      children[name] = node
      return node
    }
  }

  private static func visit(
    _ node: Node, at path: String, isRoot: Bool, skippingOutput: Bool, into out: inout Listing
  ) {
    let name = PathMeta.baseName(path)
    if !isRoot && (name.hasPrefix(".") || (skippingOutput && name.lowercased() == "output")) {
      return
    }
    if isPackageName(name) {
      out.packages.append(path)
      return
    }
    for entry in node.children.keys.sorted(by: { $0.utf8.lexicographicallyPrecedes($1.utf8) }) {
      guard let child = node.children[entry] else { continue }
      let childPath = path.hasSuffix("/") ? path + entry : path + "/" + entry
      if child.children.isEmpty, child.isFile {
        out.files.append(childPath)
      } else {
        visit(child, at: childPath, isRoot: false, skippingOutput: skippingOutput, into: &out)
      }
    }
  }

  /// A package by its name alone (no Finder on a bucket): a project, an app bundle.
  private static func isPackageName(_ name: String) -> Bool {
    let ext = (name.split(separator: ".").count > 1 ? name.split(separator: ".").last : nil)?
      .lowercased()
    return ext == ProjectPackage.fileExtension || ext == "app"
  }
}
