internal import CryptoKit
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

  /// Where the copy of `key` of `bucket` is kept: `root/<bucket>/<digest of the key>/<name>`.
  ///
  /// The folder is a digest of the key as the bucket spells it, so two keys never share a copy
  /// — not two that differ by case on a case-insensitive volume, nor by an empty part — and no
  /// key can name a file outside `root`. The frame keeps its own name, for the eye.
  package func file(bucket: String, key: String) -> URL {
    let digest = SHA256.hash(data: Data(key.utf8)).prefix(12)
      .map { String(format: "%02x", $0) }.joined()
    let last = key.split(separator: "/").last.map(String.init) ?? ""
    let name = last.isEmpty || last == "." || last == ".." ? "frame" : last
    return root.appendingPathComponent(Self.folder(of: bucket), isDirectory: true)
      .appendingPathComponent(digest, isDirectory: true).appendingPathComponent(name)
  }

  /// A bucket's own folder under `root`: its name, which S3 keeps free of `/` and of `..`.
  private static func folder(of bucket: String) -> String {
    let name = bucket.replacingOccurrences(of: "/", with: "_")
    return name.isEmpty || name == "." || name == ".." ? "bucket" : name
  }

  /// The file holding the identity `file` was downloaded as.
  package func identityFile(of file: URL) -> URL {
    file.appendingPathExtension(Self.identityExtension)
  }

  /// The kept copy of `key` when it is the object `identity` names; `nil` when there is none, it
  /// was downloaded as another object, it no longer has that object's size, or `identity`
  /// cannot tell.
  ///
  /// An identity without an ETag (`size|`: a listing or gateway that drops them) proves nothing
  /// of a kept copy — every frame of one camera has the same size — so it is downloaded again.
  /// A copy cut short (a disk unplugged, a crash) is not the object either.
  package func copy(bucket: String, key: String, identity: String) -> URL? {
    let file = file(bucket: bucket, key: key)
    guard Self.proves(identity),
      let kept = try? String(contentsOf: identityFile(of: file), encoding: .utf8),
      kept == identity,
      let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
      identity.hasPrefix("\(size)|")
    else { return nil }
    return file
  }

  /// Whether `identity` (`size|etag`) can prove a kept copy: only with an ETag.
  package static func proves(_ identity: String?) -> Bool {
    guard let identity else { return false }
    return !identity.hasSuffix("|") && identity.contains("|")
  }

  /// Records that `file` holds the object `identity` names, once its download is whole.
  ///
  /// The copy becomes read-only: lanes reach it through links, and a tool writing through one
  /// would leave bytes the identity no longer describes.
  package func keep(_ file: URL, as identity: String) throws {
    try Data(identity.utf8).write(to: identityFile(of: file), options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: file.path)
  }

  /// Forgets the copy at `file`: before it is downloaded again, and when a download fails.
  package func drop(_ file: URL) {
    try? FileManager.default.removeItem(at: identityFile(of: file))
    try? FileManager.default.removeItem(at: file)
  }

  /// The frames of `paths` (virtual paths) a copy is kept of, whatever each was downloaded as.
  ///
  /// What an estimate made before a run's listing can know. Read once, off the main actor.
  package func kept(among paths: [String]) -> Set<String> {
    Set(
      paths.filter { path in
        guard let parts = ProjectSource.remoteParts(of: path) else { return false }
        let file = file(bucket: parts.bucket, key: parts.key)
        return FileManager.default.fileExists(atPath: file.path)
          && FileManager.default.fileExists(atPath: identityFile(of: file).path)
      })
  }

  /// The bytes the kept frames take on disk, as the scratch sweep and the Finder count them.
  package func size() -> Int64 {
    LeftoverSweep.allocatedBytes(root)
  }

  /// The extension of an identity file.
  static let identityExtension = "identity"
}
