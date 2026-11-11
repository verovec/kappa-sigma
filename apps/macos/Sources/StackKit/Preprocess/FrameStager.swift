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
    /// The frames of a bucket taken from the copies kept by an earlier run (card 0191).
    package var cached = 0
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
  /// Where a bucket's frames are kept between runs (card 0191); `nil` downloads them into the
  /// lane's folder, to go with it.
  package var cache: RemoteFrameCache?
  /// Hears how many frames of a staging came from the copies an earlier run kept, when some
  /// did: the journal says which bytes were stacked (R2).
  package var keptReport: @Sendable (_ frames: Int) -> Void = { _ in }

  /// A stager over `stores`, checking each download against `expected` and keeping the frames
  /// in `cache`; without any store, only frames of this Mac can be staged.
  package init(
    stores: [RemoteObjectStore] = [], expected: [String: String] = [:],
    cache: RemoteFrameCache? = nil
  ) {
    self.stores = Dictionary(
      stores.map { ($0.bucket, $0) }, uniquingKeysWith: { first, _ in first })
    self.expected = expected
    self.cache = cache
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
      let listed = expected[path]
      // The copy an earlier run kept is this frame only when it was downloaded as the object
      // this run listed (card 0191); linked as a frame of this Mac is.
      if let listed, let copy = cache?.copy(bucket: parts.bucket, key: parts.key, identity: listed)
      {
        try files.createSymbolicLink(atPath: destination.path, withDestinationPath: copy.path)
        staged.cached += 1
        staged.identities[path] = listed
        continue
      }
      downloads.append(
        Download(
          path: path, key: parts.key, store: store, destination: destination, expected: listed,
          // A frame no listing can prove next time is not worth keeping: it goes with its lane.
          cache: RemoteFrameCache.proves(listed) ? cache : nil))
    }
    if staged.cached > 0 { keptReport(staged.cached) }
    let total = downloads.count
    try await RemoteSnapshot.inParallel(
      downloads, width: Self.parallelism,
      work: { download in (try await download.run(), download) },
      collect: { object, download in
        staged.remote += 1
        staged.bytes += object.size
        // A download checked against the listing is the object listed: what the run listed signs
        // it, also when a side had no ETag (a `size|` would never prove a master again).
        staged.identities[download.path] = download.expected ?? object.identity
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
    /// What keeps the frame between runs; `nil` writes it into the lane.
    var cache: RemoteFrameCache?

    /// The download, a changed object said as the frame that could not be read (R2).
    ///
    /// A kept frame is downloaded into the lane like any other — its `.part` goes with the run's
    /// work folder if the app dies — then moved where it is kept and linked back. Keeping is an
    /// economy, never a condition: when it cannot be done (the folder refuses, the disk is
    /// full) the frame stays in the lane and the run goes on, as it does without a cache.
    func run() async throws -> RemoteObjectStore.Object {
      let object = try await written(to: destination)
      // Only a frame its listing can prove next time is kept (`RemoteFrameCache.proves`).
      guard let cache, let expected else { return object }
      let kept = cache.file(bucket: store.bucket, key: key)
      let files = FileManager.default
      cache.drop(kept)
      do {
        try files.createDirectory(
          at: kept.deletingLastPathComponent(), withIntermediateDirectories: true)
        try files.moveItem(at: destination, to: kept)
      } catch {
        return object
      }
      do {
        try cache.keep(kept, as: expected)
        try files.createSymbolicLink(atPath: destination.path, withDestinationPath: kept.path)
      } catch {
        // Back where Siril reads it; nothing half kept for the next run.
        try? files.removeItem(at: destination)
        try files.moveItem(at: kept, to: destination)
        cache.drop(kept)
      }
      return object
    }

    /// The object written to `file`.
    private func written(to file: URL) async throws -> RemoteObjectStore.Object {
      do {
        return try await store.download(key, to: file, expecting: expected)
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
      throw PreprocessError.remoteFrameUnavailable(
        path: folder, reason: RemoteObjectStore.words(of: error))
    }
  }

  /// The folders `keys` sit in, each once and none inside another (a listing is recursive: the
  /// parent's already holds the child's keys): what a listing has to cover, and no more.
  ///
  /// A key at the bucket's root has no folder, and then the listing is the bucket — the only
  /// case where it has to be.
  package static func folders(of keys: [String]) -> [String] {
    var folders: Set<String> = []
    for key in keys {
      folders.insert(key.lastIndex(of: "/").map { String(key[...$0]) } ?? "")
    }
    return folders.filter { folder in
      !folders.contains { $0 != folder && folder.hasPrefix($0) }
    }.sorted()
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
