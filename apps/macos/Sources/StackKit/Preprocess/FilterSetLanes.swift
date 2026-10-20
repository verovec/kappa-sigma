/// A one-shot-colour capture's broadband and dual-band exposures stack as two lanes
/// (`filtersetlanes.go`).
///
/// A dual-band clip passes ~3 nm around Hα and [OIII]; an unfiltered train the whole continuum.
/// Averaging them dilutes the lines and pollutes the star colour. The clip filter is a measured
/// value, not part of `SetKey`, so without lanes two such sets would share a channel and be
/// merged into one master.
package enum FilterSetLanes {
  /// The dual-band lane's suffix; the broadband lane keeps the plain filter name (it is the grid
  /// the dual-band master registers onto, and what an unsplit run is called already).
  package static let dualbandSuffix = "-dualband"

  /// Whether the scan holds BOTH a measured broadband and a measured dual-band light set: one
  /// verdict alone says nothing about another set, and unclassified is silence.
  package static func splits(_ inventory: Inventory) -> Bool {
    let verdicts = Set(
      inventory.sets.filter { $0.key.type == .light }.compactMap {
        inventory.filterSets[$0.key.id]
      })
    return verdicts.contains(.broadband) && verdicts.contains(.dualband)
  }

  /// The lane `set` stacks in (`laneFor`): it renames the stack, never the light, so calibration
  /// still matches on the real filter.
  package static func lane(for set: FrameSet, in inventory: Inventory, split: Bool) -> String {
    split && LightRef(set, in: inventory).filterSet == .dualband
      ? set.key.filter + dualbandSuffix : set.key.filter
  }

  /// The filter the lights were shot with.
  package static func baseFilter(of lane: String) -> String {
    lane.hasSuffix(dualbandSuffix) ? String(lane.dropLast(dualbandSuffix.count)) : lane
  }

  /// The dual-band lane among `lanes`, if the run split.
  package static func dualbandLane(in lanes: some Sequence<String>) -> String? {
    lanes.first { $0.hasSuffix(dualbandSuffix) }
  }

  /// `ordered` with the dual-band lane moved last, so the broadband master is the registration
  /// reference and defines the canvas (`dualbandLast`).
  package static func dualbandLast(_ ordered: [String]) -> [String] {
    guard let lane = dualbandLane(in: ordered) else { return ordered }
    return ordered.filter { $0 != lane } + [lane]
  }
}
