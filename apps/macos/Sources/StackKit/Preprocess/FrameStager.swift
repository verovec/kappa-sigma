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
  /// Downloads in flight at once (card 0186): a lane's transfer is the network's, not one frame's
  /// round trips in a row.
  package static let parallelism = 4

  /// The buckets this run may read, by name (a run may mix nights of two buckets).
  package var stores: [String: RemoteObjectStore]
  /// What the run listed for each remote frame, `size|etag` by virtual path (card 0186): a
  /// download that reads another object fails the lane rather than stacking bytes nothing listed.
  package var expected: [String: String]

  /// A stager over `stores`, checking each download against `expected`; without any store, only
  /// frames of this Mac can be staged.
  package init(stores: [RemoteObjectStore] = [], expected: [String: String] = [:]) {
    self.stores = Dictionary(
      stores.map { ($0.bucket, $0) }, uniquingKeysWith: { first, _ in first })
    self.expected = expected
  }

  /// Stages `paths` into `folder` in their own order, and says what came from a bucket.
  ///
  /// `progress` hears the downloads; a path of this Mac costs nothing and is not counted. The
  /// downloads run `parallelism` at once, each under its positional name: the order they end in
  /// changes nothing Siril reads.
  @discardableResult
  package func stage(
    _ paths: [String], into folder: URL, progress: @escaping Progress = { _, _, _ in }
  ) async throws -> Staged {
    let files = FileManager.default
    try files.createDirectory(at: folder, withIntermediateDirectories: true)
    var staged = Staged()
    var downloads: [Download] = []
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
      downloads.append(
        Download(
          path: path, key: parts.key, store: store, destination: destination,
          expected: expected[path]))
    }
    let total = downloads.count
    try await RemoteSnapshot.inParallel(
      downloads, width: Self.parallelism,
      work: { download in (try await download.run(), download) },
      collect: { object, download in
        staged.remote += 1
        staged.bytes += object.size
        // A store that cannot say an ETag matched on its size: the object is the one listed, and
        // what the run listed is what signs it (a `size|` would never prove a master again).
        staged.identities[download.path] =
          object.etag.isEmpty ? download.expected ?? object.identity : object.identity
        if staged.remote % Self.progressStep == 0 || staged.remote == total {
          progress(staged.remote, total, staged.bytes)
        }
      })
    return staged
  }

  /// One frame of a bucket to write under its positional name.
  struct Download: Sendable {
    let path: String
    let key: String
    let store: RemoteObjectStore
    let destination: URL
    let expected: String?

    /// The download, a changed object said as the frame that could not be read (R2).
    func run() async throws -> RemoteObjectStore.Object {
      do {
        return try await store.download(key, to: destination, expecting: expected)
      } catch let changed as RemoteObjectStore.Changed {
        throw PreprocessError.remoteFrameUnavailable(path: path, reason: changed.description)
      }
    }
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
  /// One listing per folder the run's keys sit in — never the whole bucket. A listing that fails
  /// stops the run with the folder named (card 0186): a frame without identity would rebuild its
  /// master and re-run its lane on every run.
  @concurrent
  package func identities(of paths: [String]) async throws -> [String: String] {
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
        let objects = try await Self.listing(prefix, of: store)
        for object in objects {
          guard let path = keys[object.key] else { continue }
          identities[path] = object.identity
        }
      }
    }
    return identities
  }

  /// `prefix` of `store`, its failure said as the folder that could not be read.
  private static func listing(_ prefix: String, of store: RemoteObjectStore) async throws
    -> [RemoteObjectStore.Object]
  {
    let folder = "s3://" + store.bucket + "/" + prefix
    do {
      return try await store.list(prefix)
    } catch {
      if error is CancellationError || Task.isCancelled { throw CancellationError() }
      throw PreprocessError.remoteFrameUnavailable(path: folder, reason: String(describing: error))
    }
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
