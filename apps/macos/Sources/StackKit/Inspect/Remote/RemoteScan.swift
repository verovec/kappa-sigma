package import Foundation

/// The inventory of an S3 prefix (card 0167).
///
/// A `RemoteSnapshot`, then today's synchronous scan over it. A first pass learns which centred pixel runs the scan asks for; they are read by range
/// and the scan runs again. A check that needs a frame's planes is never run: those frames are
/// listed in `Inventory.notCheckedRemotely`.
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
  @concurrent
  package func inventory(
    overrides: InspectOverrides = InspectOverrides(),
    progress: @escaping @Sendable (ScanProgress) -> Void = { _ in }
  ) async throws -> Inventory {
    var snapshot = try await RemoteSnapshot.load(store: store, prefix: prefix, progress: progress)
    // The runs a pass asks for can change what the next one classifies: a few passes settle it.
    for _ in 0..<3 {
      try Task.checkCancellation()
      let asked = RemoteSnapshot.Asked()
      var inventory = try InventoryBuilder(
        timeZone: timeZone, pixels: snapshot.pixels(asked), source: snapshot.source
      ).scan(paths: [snapshot.root], overrides: overrides, progress: progress)
      let missing = asked.missingSamples
      if missing.isEmpty {
        inventory.notCheckedRemotely = asked.framesNeedingPlanes
        return inventory
      }
      try await snapshot.fetchSamples(missing, store: store)
    }
    throw RemoteScanError.unsettled(prefix)
  }
}

/// Why a remote scan failed beyond the store's own errors.
package enum RemoteScanError: Error, Equatable {
  /// Three passes still asked for new pixel runs.
  case unsettled(String)
}
