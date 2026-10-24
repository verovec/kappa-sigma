internal import StackKit

/// What the next run redoes (card 0100), said by the Stacking stage before Run.
extension ProjectWindowModel {
  /// The checked nights of the last scan, against the folders the latest stack was built from;
  /// `nil` without a scan or a checked series.
  package var restackPlan: RestackPlan? {
    RestackPlan(
      series: series,
      nightSourceIDs: sources.filter { $0.kind == .night }.map(\.id),
      lastStackSourceIDs: stacks.last?.sourceIDs)
  }

  /// Every night is being rescanned with no scan to show yet (after Add a night): Run waits, so
  /// the plan it applies is on screen before it starts.
  package var awaitsRescan: Bool { isScanning && scan == nil }

  /// `request` adds a night, through the sheet, to a project that has some.
  ///
  /// The sheet planned only the new folders (settled or not), so every night is rescanned after
  /// Add and the Stacking stage shows the full re-stack the next run is. Add again of folders
  /// already recorded (a retry) changes no night.
  func addsANight(_ request: ImportRequest) -> Bool {
    let recorded = Set(nightPaths.map(Self.standardPath))
    return importing != nil && !recorded.isEmpty
      && request.paths.contains { !recorded.contains(Self.standardPath($0)) }
  }
}
