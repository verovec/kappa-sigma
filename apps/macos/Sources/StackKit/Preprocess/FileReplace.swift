internal import Foundation

/// How the pipeline puts a Siril output in place: links resolved (Siril's `link` sequences are
/// symlinks), the previous file replaced.
enum FileReplace {
  /// Copies `source` over `target`.
  static func copy(_ source: URL, over target: URL) throws {
    try? FileManager.default.removeItem(at: target)
    try FileManager.default.copyItem(at: source.resolvingSymlinksInPath(), to: target)
  }
}
