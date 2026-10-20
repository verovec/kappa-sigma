package import Foundation

/// How the pipeline puts a Siril output in place: links resolved (Siril's `link` sequences are
/// symlinks), the previous file replaced.
package enum FileReplace {
  /// Copies `source` over `target`.
  package static func copy(_ source: URL, over target: URL) throws {
    try? FileManager.default.removeItem(at: target)
    try FileManager.default.copyItem(at: source.resolvingSymlinksInPath(), to: target)
  }

  /// Turns a link into a private copy of what it points to, so writing to `url` never reaches
  /// the link's target (a capture, under R7); a plain file is left alone.
  package static func detach(_ url: URL) throws {
    let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
    guard values.isSymbolicLink == true else { return }
    let copy = url.deletingLastPathComponent()
      .appendingPathComponent("." + url.lastPathComponent + ".detach")
    try? FileManager.default.removeItem(at: copy)
    try FileManager.default.copyItem(at: url.resolvingSymlinksInPath(), to: copy)
    // Removing a link removes the link alone; the copy then takes its name.
    try FileManager.default.removeItem(at: url)
    try FileManager.default.moveItem(at: copy, to: url)
  }
}
