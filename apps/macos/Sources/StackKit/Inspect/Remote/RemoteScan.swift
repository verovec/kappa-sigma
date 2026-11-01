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
  ///
  /// A check that needed a frame's planes leaves its whole set unchecked (a set's verdict is read
  /// on a sample of its frames): every frame of such a set is in `notCheckedRemotely`.
  @concurrent
  package func inventory(
    overrides: InspectOverrides = InspectOverrides(),
    progress: @escaping @Sendable (ScanProgress) -> Void = { _ in }
  ) async throws -> Inventory {
    var snapshot = try await RemoteSnapshot.load(store: store, prefix: prefix, progress: progress)
    progress(.classifying)
    // The runs a pass asks for can change what the next one classifies: a few passes settle it;
    // the last pass answers with what it has (a run still missing reads as unreadable).
    for pass in 0..<Self.passes {
      try Task.checkCancellation()
      let asked = RemoteSnapshot.Asked()
      var inventory = try InventoryBuilder(
        timeZone: timeZone, pixels: snapshot.pixels(asked), source: snapshot.source
      ).scan(paths: [snapshot.root], overrides: overrides)
      let missing = asked.missingSamples
      if missing.isEmpty || pass == Self.passes - 1 {
        inventory.notCheckedRemotely = Self.unchecked(asked.framesNeedingPlanes, in: inventory)
        return inventory
      }
      try await snapshot.fetchSamples(missing, store: store)
    }
    return Inventory(root: snapshot.root, frames: [])
  }

  /// Scan passes at most: the first learns the runs, the next reads with them.
  static let passes = 3

  /// The frames left unchecked: those whose planes were asked, every frame of their sets, and —
  /// when a BIAS or DARK was asked (the pedestal the dual-band verdict of every light set reads)
  /// — every light.
  static func unchecked(_ asked: [String], in inventory: Inventory) -> [String] {
    let named = Set(asked)
    var frames = named
    for set in inventory.sets where set.frames.contains(where: { named.contains($0.path) }) {
      frames.formUnion(set.frames.map(\.path))
    }
    let pedestal = inventory.frames.contains {
      named.contains($0.path) && ($0.type == .bias || $0.type == .dark)
    }
    if pedestal { frames.formUnion(inventory.frames.filter { $0.type == .light }.map(\.path)) }
    return frames.sorted()
  }
}
