package import Foundation
package import ImageKit
internal import ProjectKit
internal import Synchronization

/// An S3 prefix read in advance for the synchronous scan (card 0167): the listing as virtual paths
/// `s3://<bucket>/<key>`, every FITS header (read by ranges, grown until `END`), the small side
/// files (SharpCap sidecars, `info.txt`) and the centred pixel runs the scan asked for.
///
/// Whole frames are never downloaded (PO 01/11): a check that needs a frame's planes is not run
/// and its frame is named in `Inventory.notCheckedRemotely` (R2: shown, never silently passed).
package struct RemoteSnapshot: Sendable {
  /// The first bytes read of a frame, then each extension until the header's `END`.
  static let headerChunk: Int64 = 64 << 10
  /// A side file larger than this is no sidecar or manifest: never downloaded.
  static let sideFileLimit: Int64 = 1 << 20
  /// Requests in flight at once.
  static let parallelism = 8
  /// The files a scan walks under one prefix at most (card 0186): beyond, the prefix is refused
  /// and named before a header is read — a bucket's root chosen by mistake. `output/` folders,
  /// which the walk skips, do not count.
  package static let maxObjects = 20_000

  /// The virtual root of the scan: `s3://<bucket>/<prefix>` without its trailing `/`.
  package let root: String
  /// The walk of the prefix, in virtual paths.
  package let listing: InspectWalk.Listing
  /// The object behind each virtual path.
  let objects: [String: RemoteObjectStore.Object]
  /// Each FITS frame's header, or the error reading it gave (a skip warning, as on disk).
  var headers: [String: Result<FITSHeader, any Error>] = [:]
  /// The side files' bytes.
  var contents: [String: Data] = [:]
  /// The centred run read of each frame, at the largest count asked.
  var runs: [String: [Double]] = [:]
  /// Frames no further centred run is fetched for (a layout the scan cannot locate, a short or
  /// failed answer): a run already held still answers smaller counts; any other read fails as an
  /// unreadable file does on disk and names the frame.
  var unreadable: Set<String> = []
  /// The side files that failed to read (path → why): absent for the scan, said as warnings.
  package internal(set) var sideFailures: [String: String] = [:]

  /// The virtual path of `key` in `bucket`.
  package static func path(bucket: String, key: String) -> String {
    "s3://" + bucket + "/" + key
  }

  /// Lists `prefix` of `store` and reads every FITS header and side file under it; `progress`
  /// hears the listing, then the headers read.
  ///
  /// `cache` is what a previous scan of the same prefix read (card 0168): a key the bucket answers
  /// with the same ETag is taken from it and never read again.
  @concurrent
  package static func load(
    store: RemoteObjectStore, prefix: String, cache: RemoteScanCache = .empty,
    progress: @escaping @Sendable (ScanProgress) -> Void = { _ in }
  ) async throws -> Self {
    progress(.listing)
    // The root is the spelling the project stores for the source (ProjectSource.remotePath): no
    // trailing `/`, `s3://bucket` for a whole bucket.
    let key = ProjectSource.key(prefix)
    let folder = key.isEmpty ? "" : key + "/"
    let found = try await store.list(folder)
    let root = ProjectSource.remotePath(bucket: store.bucket, prefix: key)
    var objects: [String: RemoteObjectStore.Object] = [:]
    for object in found where object.key.hasPrefix(folder) {
      objects[path(bucket: store.bucket, key: object.key)] = object
    }
    let listing = InspectWalk.listing(
      keys: found.filter { $0.key.hasPrefix(folder) }.map {
        String($0.key.dropFirst(folder.count))
      },
      under: root, skippingOutput: true)
    guard listing.files.count <= maxObjects else {
      throw InspectError.remoteTooLarge(path: root, limit: maxObjects)
    }
    var snapshot = Self(root: root, listing: listing, objects: objects)
    snapshot.seed(from: cache)
    try await snapshot.readHeadersAndSideFiles(store: store, progress: progress)
    return snapshot
  }

  /// Takes from `cache` what the bucket still answers at the same ETag and size.
  ///
  /// Everything else is read again; a cached entry is never a measurement, only bytes.
  mutating func seed(from cache: RemoteScanCache) {
    // The walk's files, not every listed key: what the scan never reads (an `output/` folder, a
    // sidecar whose frame is gone) is not carried from one cache to the next.
    for path in listing.files {
      guard let object = objects[path], let entry = cache.entries[object.key],
        entry.etag == object.etag, entry.size == object.size
      else { continue }
      if let cards = entry.header {
        headers[path] = .success(FITSHeader(cards: cards.map(FITSHeader.Card.init(raw:))))
      }
      if let contents = entry.contents { self.contents[path] = contents }
    }
  }

  /// What this snapshot read, to keep for the next scan of the same prefix (card 0168): the files
  /// the walk just answered, so a key the bucket no longer holds is not carried over.
  package var cache: RemoteScanCache {
    var entries: [String: RemoteScanCache.Entry] = [:]
    for path in listing.files {
      guard let object = objects[path] else { continue }
      var entry = RemoteScanCache.Entry(etag: object.etag, size: object.size)
      if case .success(let header)? = headers[path] { entry.header = header.cards.map(\.raw) }
      // A side file bigger than a sidecar is read again rather than carried in the body.
      if let bytes = contents[path], bytes.count <= RemoteScanCache.maxCachedSideFileBytes {
        entry.contents = bytes
      }
      // An object nothing was read of (a preview image, a failed header) stays out of the body.
      guard entry.header != nil || entry.contents != nil else { continue }
      entries[object.key] = entry
    }
    return RemoteScanCache(entries: entries)
  }

  /// The source the scan reads: this snapshot's listing, headers and side files.
  package var source: FrameSource {
    let snapshot = self
    return FrameSource(
      walk: { root, _ in
        guard InventoryBuilder.clean(root) == snapshot.root else { return InspectWalk.Listing() }
        return snapshot.listing
      },
      header: { path in
        guard let header = snapshot.headers[path] else { throw NotRead(path: path) }
        return try header.get()
      },
      contents: { snapshot.contents[$0] })
  }

  /// The pixels the scan reads: centred runs this snapshot holds; whatever else is asked is told
  /// to `asked` (a run to fetch, a frame whose planes are never read) and not answered.
  package func pixels(_ asked: Asked) -> PixelReader {
    let snapshot = self
    return PixelReader(
      planes: { path in
        asked.planes(path)
        throw NotRead(path: path)
      },
      centerSample: { path, count in
        // A run held answers whatever the frame's later reads failed to fetch.
        if let values = try? snapshot.sample(path, count: count) { return values }
        if snapshot.unreadable.contains(path) {
          asked.failed(path)
        } else {
          asked.sample(path, count: count)
        }
        throw NotRead(path: path)
      })
  }

  /// The centred run of `count` values of `path`, cut from the larger run held, or `nil`.
  func sample(_ path: String, count: Int) throws -> [Double]? {
    guard let held = runs[path], case .success(let header)? = headers[path] else { return nil }
    let wanted = try FITSFile.centerRun(of: header, maxCount: count)
    let have = try FITSFile.centerRun(of: header, maxCount: held.count)
    guard wanted.count <= have.count else { return nil }
    let offset = wanted.first - have.first
    return Array(held[offset..<offset + wanted.count])
  }

  /// What the scan asked of the pixel reader that the snapshot could not answer.
  package final class Asked: Sendable {
    private let state = Mutex(
      (planes: Set<String>(), samples: [String: Int](), failed: Set<String>()))

    /// An empty record.
    package init() {}

    /// The frames whose planes a check asked for.
    package var framesNeedingPlanes: [String] { state.withLock { $0.planes.sorted() } }
    /// The centred runs to fetch: the largest count asked per frame.
    package var missingSamples: [String: Int] { state.withLock { $0.samples } }
    /// Every frame a pixel read of this pass did not answer: planes asked, a run missing or
    /// unreadable — each one's measurement was not made.
    package var framesUnanswered: [String] {
      state.withLock { $0.planes.union($0.failed).union($0.samples.keys).sorted() }
    }

    func failed(_ path: String) { state.withLock { _ = $0.failed.insert(path) } }

    func planes(_ path: String) { state.withLock { _ = $0.planes.insert(path) } }

    func sample(_ path: String, count: Int) {
      state.withLock { $0.samples[path] = max($0.samples[path] ?? 0, count) }
    }
  }

  /// A read the snapshot holds no answer for.
  struct NotRead: Error, CustomStringConvertible {
    let path: String
    var description: String { "not read from S3: \(path)" }
  }
}
