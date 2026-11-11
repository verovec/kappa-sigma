package import Foundation
internal import ProjectKit

/// The frames a project's runs downloaded from buckets, kept between runs (card 0191).
///
/// One copy a frame under `root/<bucket>/<key>`, beside a small file holding the identity it was
/// downloaded as (`size|etag`, as the run listed it). A run links a kept copy into its lane only
/// when that identity is the one its own listing answers: an object uploaded again is downloaded
/// again, never stacked stale (R2). The folder is the app's own, outside every capture folder
/// (R7) and outside the project package; nothing here is ever written to a bucket.
package struct RemoteFrameCache: Sendable, Equatable {
  /// The folder of this project's copies.
  package var root: URL

  /// The copies kept under `root`.
  package init(root: URL) {
    self.root = root
  }

  /// Where the copy of `key` of `bucket` is kept.
  ///
  /// Always under `root/<bucket>/`: a key is the bucket's own spelling, so its empty, `.` and
  /// `..` parts are spelled out rather than walked.
  package func file(bucket: String, key: String) -> URL {
    let parts =
      ([bucket] + key.split(separator: "/", omittingEmptySubsequences: true).map(String.init))
      .map { part in part == "." ? "%2E" : part == ".." ? "%2E%2E" : part }
    return parts.reduce(root) { $0.appendingPathComponent($1) }
  }

  /// The file holding the identity `file` was downloaded as.
  package func identityFile(of file: URL) -> URL {
    file.appendingPathExtension(Self.identityExtension)
  }

  /// The kept copy of `key` when it is the object `identity` names; `nil` when there is none, or
  /// it was downloaded as another object.
  package func copy(bucket: String, key: String, identity: String) -> URL? {
    let file = file(bucket: bucket, key: key)
    guard FileManager.default.fileExists(atPath: file.path),
      let kept = try? String(contentsOf: identityFile(of: file), encoding: .utf8),
      kept == identity
    else { return nil }
    return file
  }

  /// Records that `file` holds the object `identity` names, once its download is whole.
  package func keep(_ file: URL, as identity: String) throws {
    try Data(identity.utf8).write(to: identityFile(of: file), options: .atomic)
  }

  /// Forgets the copy at `file`: before it is downloaded again, and when a download fails.
  package func drop(_ file: URL) {
    try? FileManager.default.removeItem(at: identityFile(of: file))
    try? FileManager.default.removeItem(at: file)
  }

  /// A copy of the frame at the virtual `path` is kept, whatever it was downloaded as: what an
  /// estimate made before the run's listing can know.
  package func holds(_ path: String) -> Bool {
    guard let parts = ProjectSource.remoteParts(of: path) else { return false }
    let file = file(bucket: parts.bucket, key: parts.key)
    return FileManager.default.fileExists(atPath: file.path)
      && FileManager.default.fileExists(atPath: identityFile(of: file).path)
  }

  /// The bytes the kept frames take on disk (their identity files are not counted).
  package func size() -> Int64 {
    let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
    guard
      let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys)
    else { return 0 }
    var total: Int64 = 0
    for case let url as URL in walker where url.pathExtension != Self.identityExtension {
      guard let values = try? url.resourceValues(forKeys: Set(keys)),
        values.isRegularFile == true
      else { continue }
      total += Int64(values.fileSize ?? 0)
    }
    return total
  }

  /// The extension of an identity file.
  static let identityExtension = "identity"
}
