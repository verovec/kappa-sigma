package import Foundation
internal import ImageKit
internal import ProjectKit
internal import Synchronization

/// The inventory of a capture read from several roots at once (card 0190): folders of this Mac
/// and S3 prefixes, classified together.
///
/// Each prefix is a `RemoteSnapshot`; today's synchronous scan then runs once over every root, so
/// grouping, verdicts and completeness see the union — the calibration under one root serves the
/// lights of another, wherever each is read from. A first pass learns which centred pixel runs
/// the scan asks of the buckets; they are read by range and the scan runs again. A check that
/// needs the planes of a bucket frame is never run: the frames its verdict spans are listed in
/// `Inventory.notCheckedRemotely` (`RemoteScan.unchecked`). A prefix that cannot be read fails the
/// scan: the other roots alone would be another capture (R2).
package struct CaptureScan: Sendable {
  /// One S3 prefix of the capture.
  package struct Prefix: Sendable {
    /// The bucket.
    package var store: RemoteObjectStore
    /// The prefix scanned (a virtual folder).
    package var prefix: String
    /// What a previous scan of this prefix read (card 0168): not read again at the same ETag.
    package var cache: RemoteScanCache

    /// `prefix` of `store`, sparing the reads `cache` holds.
    package init(store: RemoteObjectStore, prefix: String, cache: RemoteScanCache = .empty) {
      self.store = store
      self.prefix = prefix
      self.cache = cache
    }
  }

  /// Where one part of the capture is read from.
  package enum Root: Sendable {
    /// A folder of this Mac.
    case folder(String)
    /// A prefix of a bucket.
    case prefix(Prefix)
  }

  /// The roots, in the order the scan walks them.
  package var roots: [Root]
  /// The site's zone: it decides each frame's observing night.
  package var timeZone: TimeZone

  /// A scan of `roots` in `timeZone`.
  package init(roots: [Root], timeZone: TimeZone = .current) {
    self.roots = roots
    self.timeZone = timeZone
  }

  /// An inventory and what reading its prefixes fetched, to keep for the next scan.
  package struct Scanned: Sendable {
    /// The inventory the scan answered.
    package let inventory: Inventory
    /// What was read of each prefix, by its root (`s3://bucket/prefix`).
    package let caches: [String: RemoteScanCache]
  }

  /// The inventory of the roots with the user's `overrides`; `progress` hears each prefix being
  /// read, then the folders walked.
  @concurrent
  package func scan(
    overrides: InspectOverrides = InspectOverrides(),
    progress: @escaping @Sendable (ScanProgress) -> Void = { _ in }
  ) async throws -> Scanned {
    var loaded: [Loaded] = []
    var paths: [String] = []
    for root in Self.distinct(roots) {
      switch root {
      case .folder(let path): paths.append(path)
      case .prefix(let prefix):
        try Task.checkCancellation()
        let snapshot = try await RemoteSnapshot.load(
          store: prefix.store, prefix: prefix.prefix, cache: prefix.cache, progress: progress)
        loaded.append(Loaded(snapshot: snapshot, store: prefix.store))
        paths.append(snapshot.root)
      }
    }
    // The folders are walked aloud, their own steps ending in `classifying`; a capture of
    // buckets alone already told its reads and goes straight to it.
    let silent: @Sendable (ScanProgress) -> Void = { _ in }
    let walking = loaded.count < paths.count ? progress : silent
    if loaded.count == paths.count { progress(.classifying) }
    // What a pass read of this Mac serves the next: only the buckets' answers change between two.
    let disk = DiskReads()
    // The runs a pass asks for can change what the next one classifies: a few passes settle it;
    // the last pass answers with what it has (every read it misses names its frame).
    var pass = 1
    while true {
      try Task.checkCancellation()
      let asked = RemoteSnapshot.Asked()
      let inventory = try InventoryBuilder(
        timeZone: timeZone, pixels: Self.pixels(loaded, asked), source: Self.source(loaded, disk)
      ).scan(paths: paths, overrides: overrides, progress: pass == 1 ? walking : silent)
      let missing = asked.missingSamples
      guard !missing.isEmpty, pass < RemoteScan.passes else {
        return Scanned(
          inventory: Self.finished(inventory, loaded, asked),
          caches: Dictionary(
            loaded.map { ($0.snapshot.root, $0.snapshot.cache) }, uniquingKeysWith: { $1 }))
      }
      for index in loaded.indices {
        let own = missing.filter { loaded[index].holds($0.key) }
        guard !own.isEmpty else { continue }
        try await loaded[index].snapshot.fetchSamples(own, store: loaded[index].store)
      }
      pass += 1
    }
  }

  /// `roots` without a prefix another prefix of the same bucket already covers (or repeats):
  /// the outer one lists the inner one's frames, and a frame walked twice would be stacked twice.
  static func distinct(_ roots: [Root]) -> [Root] {
    let spelled = roots.map { root -> String? in
      guard case .prefix(let prefix) = root else { return nil }
      return ProjectSource.remotePath(
        bucket: prefix.store.bucket, prefix: ProjectSource.key(prefix.prefix))
    }
    return roots.indices.filter { index in
      guard let own = spelled[index] else { return true }
      return !spelled.indices.contains { other in
        guard other != index, let outer = spelled[other] else { return false }
        return own.hasPrefix(outer + "/") || (own == outer && other < index)
      }
    }.map { roots[$0] }
  }

  /// What the scan read of this Mac's folders, kept from one pass to the next.
  ///
  /// Listings and headers. Pixels are read again by a pass that needs them — a centred run is megabytes a
  /// frame, and a second pass only happens when a bucket frame is typed by its pixels.
  final class DiskReads: Sendable {
    private struct State {
      var listings: [String: InspectWalk.Listing] = [:]
      var headers: [String: Result<FITSHeader, any Error>] = [:]
    }
    private let state = Mutex(State())

    func listing(under root: String, skippingOutput: Bool) throws -> InspectWalk.Listing {
      let key = "\(skippingOutput)|\(root)"
      if let held = state.withLock({ $0.listings[key] }) { return held }
      let read = try FrameSource.files.listing(under: root, skippingOutput: skippingOutput)
      state.withLock { $0.listings[key] = read }
      return read
    }

    func header(_ path: String) throws -> FITSHeader {
      if let held = state.withLock({ $0.headers[path] }) { return try held.get() }
      let read = Result { try FrameSource.files.header(path) }
      state.withLock { $0.headers[path] = read }
      return try read.get()
    }
  }

  /// A prefix once listed and read, with the bucket its pixel runs come from.
  struct Loaded: Sendable {
    var snapshot: RemoteSnapshot
    var store: RemoteObjectStore

    /// `path` is this prefix's root or lies under it.
    func holds(_ path: String) -> Bool {
      path == snapshot.root || path.hasPrefix(snapshot.root + "/")
    }
  }

  /// What reads `path`: the one of `readers` whose prefix holds it (`distinct` leaves no prefix
  /// inside another), `fallback` for a path of this Mac.
  static func pick<Reader>(_ path: String, _ readers: [(Loaded, Reader)], or fallback: Reader)
    -> Reader
  {
    let clean = InventoryBuilder.clean(path)
    return readers.first { $0.0.holds(clean) }?.1 ?? fallback
  }

  /// Listings, headers and side files: each prefix's snapshot, the disk for everything else.
  static func source(_ loaded: [Loaded], _ disk: DiskReads) -> FrameSource {
    guard !loaded.isEmpty else { return .files }
    let local = FrameSource(
      walk: { root, skippingOutput in
        try disk.listing(under: root, skippingOutput: skippingOutput)
      },
      header: { path in try disk.header(path) },
      contents: { path in FrameSource.files.contents(path) })
    let sources = loaded.map { ($0, $0.snapshot.source) }
    return FrameSource(
      walk: { root, skippingOutput in
        try Self.pick(root, sources, or: local).listing(under: root, skippingOutput: skippingOutput)
      },
      header: { path in try Self.pick(path, sources, or: local).header(path) },
      contents: { path in Self.pick(path, sources, or: local).contents(path) })
  }

  /// Pixels: the centred runs each snapshot holds (what it lacks is told to `asked`), the files
  /// of this Mac for everything else.
  static func pixels(_ loaded: [Loaded], _ asked: RemoteSnapshot.Asked) -> PixelReader {
    guard !loaded.isEmpty else { return .files }
    let readers = loaded.map { ($0, $0.snapshot.pixels(asked)) }
    return PixelReader(
      planes: { path in try Self.pick(path, readers, or: .files).planes(path) },
      centerSample: { path, count in
        try Self.pick(path, readers, or: .files).centerSample(path, count)
      })
  }

  /// `inventory` with the bucket frames whose checks were not made, and the side files that
  /// failed, prefix by prefix.
  static func finished(_ inventory: Inventory, _ loaded: [Loaded], _ asked: RemoteSnapshot.Asked)
    -> Inventory
  {
    var inventory = inventory
    inventory.notCheckedRemotely = RemoteScan.unchecked(
      asked.framesUnanswered, planes: asked.framesNeedingPlanes, in: inventory)
    for prefix in loaded {
      for (path, why) in prefix.snapshot.sideFailures.sorted(by: { $0.key < $1.key }) {
        inventory.warnings.append(
          "s3: could not read \(InspectWalk.relative(path, to: prefix.snapshot.root)): \(why)")
      }
    }
    return inventory
  }
}
