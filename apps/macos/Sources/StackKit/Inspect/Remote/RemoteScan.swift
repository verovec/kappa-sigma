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
    var snapshot = try await RemoteSnapshot.load(store: store, prefix: prefix, progress: progress)
    progress(.classifying)
    // The runs a pass asks for can change what the next one classifies: a few passes settle it;
    // the last pass answers with what it has (every read it misses names its frame).
    for _ in 1..<Self.passes {
      try Task.checkCancellation()
      let asked = RemoteSnapshot.Asked()
      let inventory = try scan(snapshot, asked: asked, overrides: overrides)
      guard !asked.missingSamples.isEmpty else { return finished(inventory, snapshot, asked) }
      try await snapshot.fetchSamples(asked.missingSamples, store: store)
    }
    try Task.checkCancellation()
    let asked = RemoteSnapshot.Asked()
    return finished(try scan(snapshot, asked: asked, overrides: overrides), snapshot, asked)
  }

  /// Today's scan over `snapshot`, its unanswered pixel reads told to `asked`.
  private func scan(
    _ snapshot: RemoteSnapshot, asked: RemoteSnapshot.Asked, overrides: InspectOverrides
  ) throws -> Inventory {
    try InventoryBuilder(
      timeZone: timeZone, pixels: snapshot.pixels(asked), source: snapshot.source
    ).scan(paths: [snapshot.root], overrides: overrides)
  }

  /// `inventory` with the frames whose checks were not made, and the side files that failed.
  private func finished(
    _ inventory: Inventory, _ snapshot: RemoteSnapshot, _ asked: RemoteSnapshot.Asked
  ) -> Inventory {
    var inventory = inventory
    inventory.notCheckedRemotely = Self.unchecked(
      asked.framesUnanswered, planes: asked.framesNeedingPlanes, in: inventory)
    for (path, why) in snapshot.sideFailures.sorted(by: { $0.key < $1.key }) {
      inventory.warnings.append(
        "s3: could not read \(InspectWalk.relative(path, to: snapshot.root)): \(why)")
    }
    return inventory
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
