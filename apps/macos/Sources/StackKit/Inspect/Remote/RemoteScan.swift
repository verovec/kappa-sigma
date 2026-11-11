package import Foundation

/// The inventory of an S3 prefix (card 0167).
///
/// A `RemoteSnapshot`, then today's synchronous scan over it. A first pass learns which centred pixel runs the scan asks for; they are read by range
/// and the scan runs again. A check that needs a frame's planes is never run: the frames its
/// verdict spans are listed in `Inventory.notCheckedRemotely` (`unchecked`).
package struct RemoteScan: Sendable {
  /// The bucket.
  package var store: RemoteObjectStore
  /// The prefix scanned (a virtual folder).
  package var prefix: String
  /// The site's zone: it decides each frame's observing night.
  package var timeZone: TimeZone

  /// A scan of `prefix` of `store` in `timeZone`.
  package init(store: RemoteObjectStore, prefix: String, timeZone: TimeZone = .current) {
    self.store = store
    self.prefix = prefix
    self.timeZone = timeZone
  }

  /// The inventory of the prefix with the user's `overrides`; `progress` hears the reads.
  ///
  /// Every frame whose checks were not made is in `notCheckedRemotely` (`unchecked`); a side file
  /// that could not be read is a warning.
  @concurrent
  package func inventory(
    overrides: InspectOverrides = InspectOverrides(),
    progress: @escaping @Sendable (ScanProgress) -> Void = { _ in }
  ) async throws -> Inventory {
    try await scan(overrides: overrides, progress: progress).inventory
  }

  /// The inventory of the prefix and what this scan read, to keep for the next one (card 0168).
  ///
  /// `cache` is the body a previous scan of the same prefix answered: a key the bucket still
  /// holds at the same ETag is not read again. The cache returned describes the keys the listing
  /// just answered — one the bucket no longer holds is gone from both.
  @concurrent
  package func scan(
    cache: RemoteScanCache = .empty, overrides: InspectOverrides = InspectOverrides(),
    progress: @escaping @Sendable (ScanProgress) -> Void = { _ in }
  ) async throws -> Scanned {
    // One prefix of `CaptureScan` (card 0190): the same snapshot, the same passes.
    let scanned = try await CaptureScan(
      roots: [.prefix(.init(store: store, prefix: prefix, cache: cache))], timeZone: timeZone
    ).scan(overrides: overrides, progress: progress)
    return Scanned(inventory: scanned.inventory, cache: scanned.caches.values.first ?? .empty)
  }

  /// An inventory and what reading it fetched, for the next scan of the same prefix.
  package struct Scanned: Sendable {
    /// The inventory the scan answered.
    package let inventory: Inventory
    /// What was read, to keep with the source (`ProjectStore.setRemoteScan`).
    package let cache: RemoteScanCache
  }

  /// Scan passes at most: the first learns the runs, the next reads with them.
  static let passes = 3

  /// The frames left unchecked, as StackKit's own decisions span them: a frame a read missed and
  /// every frame of its set (a set's verdict is read on a sample); a LIGHT whose planes were asked
  /// (the CFA probe, decided per instrument as `clearSpuriousBayer` groups them) and every frame
  /// of its instrument; a BIAS or DARK whose planes were asked (the pedestal every light set's
  /// dual-band verdict reads) and every light.
  package static func unchecked(_ missed: [String], planes: [String], in inventory: Inventory)
    -> [String]
  {
    let named = Set(missed)
    var frames = named
    for set in inventory.sets where set.frames.contains(where: { named.contains($0.path) }) {
      frames.formUnion(set.frames.map(\.path))
    }
    let asked = inventory.frames.filter { Set(planes).contains($0.path) }
    let instruments = Set(asked.filter { $0.type == .light }.map(\.instrument))
    let pedestal = asked.contains { $0.type == .bias || $0.type == .dark }
    for frame in inventory.frames
    where instruments.contains(frame.instrument) || (pedestal && frame.type == .light) {
      frames.insert(frame.path)
    }
    return frames.sorted()
  }
}
