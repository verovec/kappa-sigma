package import Foundation
internal import ProjectKit

/// Puts a lane's frames where Siril reads them (card 0154): a symlink for a frame of this Mac,
/// a download for one that lives in a bucket — under the same positional names either way, so a
/// lane of local frames emits byte-identical scripts and masters.
///
/// The frames go with the lane: the caller's `defer` removes the folder, and a download that
/// fails leaves neither a `.part` nor a frame nothing read (R2 — a short lane would otherwise
/// stack as if the bucket had held fewer frames).
package struct FrameStager: Sendable {
  /// What one staging answered: how many frames came from a bucket, their bytes, and what
  /// identifies each remote frame now (`size|etag`) for the resume digest.
  package struct Staged: Sendable, Equatable {
    /// The frames downloaded.
    package var remote = 0
    /// The bytes downloaded.
    package var bytes: Int64 = 0
    /// Virtual path → `size|etag`, as the bucket answered it.
    package var identities: [String: String] = [:]
    /// Where each frame was staged, in the order it was given: what Siril reads, and what a
    /// step reading the frames themselves must use (a virtual path reads nothing).
    package var files: [URL] = []
  }

  /// Hears each frame staged: how many of how many, and the bytes so far.
  package typealias Progress = @Sendable (_ done: Int, _ total: Int, _ bytes: Int64) -> Void

  /// One line every `progressStep` frames, and always on the last.
  static let progressStep = 8

  /// The buckets this run may read, by name (a run may mix nights of two buckets).
  package var stores: [String: RemoteObjectStore]

  /// A stager over `stores`; without any, only frames of this Mac can be staged.
  package init(stores: [RemoteObjectStore] = []) {
    self.stores = Dictionary(
      stores.map { ($0.bucket, $0) }, uniquingKeysWith: { first, _ in first })
  }

  /// Stages `paths` into `folder` in their own order, and says what came from a bucket.
  ///
  /// `progress` hears the downloads; a path of this Mac costs nothing and is not counted.
  @discardableResult
  package func stage(
    _ paths: [String], into folder: URL, progress: @escaping Progress = { _, _, _ in }
  ) async throws -> Staged {
    let files = FileManager.default
    try files.createDirectory(at: folder, withIntermediateDirectories: true)
    var staged = Staged()
    let remote = paths.filter { ProjectSource.remoteParts(of: $0) != nil }.count
    for (index, path) in paths.enumerated() {
      try Task.checkCancellation()
      let destination = folder.appendingPathComponent(Self.name(of: path, at: index))
      staged.files.append(destination)
      try? files.removeItem(at: destination)
      guard let parts = ProjectSource.remoteParts(of: path) else {
        try files.createSymbolicLink(
          atPath: destination.path,
          withDestinationPath: URL(fileURLWithPath: path).standardizedFileURL.path)
        continue
      }
      guard let store = stores[parts.bucket] else {
        throw PreprocessError.remoteFrameUnavailable(
          path: path, reason: "no connection for the bucket \(parts.bucket) in this run")
      }
      let object = try await store.download(parts.key, to: destination)
      staged.remote += 1
      staged.bytes += object.size
      staged.identities[path] = object.identity
      if staged.remote % Self.progressStep == 0 || staged.remote == remote {
        progress(staged.remote, remote, staged.bytes)
      }
    }
    return staged
  }

  /// The buckets `paths` name that this run has no connection for, sorted.
  ///
  /// The run refuses before Siril starts rather than failing a lane half way (card 0154): the
  /// frames are not there to be read at all, which is a reason the user can act on.
  package func missingBuckets(of paths: [String]) -> [String] {
    var missing: Set<String> = []
    for path in paths {
      guard let parts = ProjectSource.remoteParts(of: path), stores[parts.bucket] == nil else {
        continue
      }
      missing.insert(parts.bucket)
    }
    return missing.sorted()
  }

  /// What identifies each remote frame of `paths` right now (`size|etag`), by virtual path.
  ///
  /// One listing per bucket, over the longest prefix the run's keys share — never the whole
  /// bucket. A listing that fails answers nothing for that bucket: the digest then falls back to
  /// the path alone, which is what a missing local file already does.
  @concurrent
  package func identities(of paths: [String]) async -> [String: String] {
    var byBucket: [String: [String: String]] = [:]
    for path in paths {
      guard let parts = ProjectSource.remoteParts(of: path) else { continue }
      byBucket[parts.bucket, default: [:]][parts.key] = path
    }
    var identities: [String: String] = [:]
    for (bucket, keys) in byBucket {
      guard let store = stores[bucket] else { continue }
      // One listing per folder the keys sit in: a run whose lights and calibration live apart
      // shares no prefix, and listing the empty one would page the whole bucket.
      for prefix in Self.folders(of: Array(keys.keys)) {
        guard let objects = try? await store.list(prefix) else { continue }
        for object in objects {
          guard let path = keys[object.key] else { continue }
          identities[path] = object.identity
        }
      }
    }
    return identities
  }

  /// The folders `keys` sit in, each once: what a listing has to cover, and no more.
  ///
  /// A key at the bucket's root has no folder, and then the listing is the bucket — the only
  /// case where it has to be.
  package static func folders(of keys: [String]) -> [String] {
    var folders: Set<String> = []
    for key in keys {
      folders.insert(key.lastIndex(of: "/").map { String(key[...$0]) } ?? "")
    }
    return folders.sorted()
  }

  /// The longest `/`-bounded prefix every key shares (`""` when they share none).
  package static func commonPrefix(of keys: [String]) -> String {
    guard var shared = keys.first else { return "" }
    for key in keys.dropFirst() {
      shared = shared.commonPrefix(with: key)
      if shared.isEmpty { return "" }
    }
    guard let slash = shared.lastIndex(of: "/") else { return "" }
    return String(shared[...slash])
  }

  /// `00001_<name>`: the name Siril's `convert` reads in order, and the one
  /// `MasterBuilder.link` has always written.
  static func name(of path: String, at index: Int) -> String {
    String(format: "%05d_", index + 1) + PathMeta.baseName(path)
  }
}
