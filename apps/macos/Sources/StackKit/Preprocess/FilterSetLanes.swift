package import FilterKit

/// A one-shot-colour capture's broadband and line-clip exposures stack as separate lanes
/// (`filtersetlanes.go`, generalised to every clip filter in card 0134).
///
/// A dual-band clip passes ~3 nm around two lines; an unfiltered train the whole continuum.
/// Averaging them dilutes the lines and pollutes the star colour. The clip filter is a measured
/// (or asserted) value, not part of `SetKey`, so without lanes two such sets would share a
/// channel and be merged into one master.
package enum FilterSetLanes {
  /// The lane suffix of a clip filter: `-<set>` for a line clip, none for broadband or unknown
  /// (the broadband lane keeps the plain filter name: it is the grid the line masters register
  /// onto, and what an unsplit run is called already).
  package static func suffix(of set: FilterSet) -> String? {
    set.lines == nil ? nil : "-" + set.rawValue
  }

  /// Whether the scan holds light sets of two different known clips (a broadband and a line
  /// clip, or two line clips): they must never share a master.
  ///
  /// One verdict alone says nothing about another set, and unclassified is silence.
  package static func splits(_ inventory: Inventory) -> Bool {
    splits(inventory, setIDs: inventory.sets.filter { $0.key.type == .light }.map(\.key.id))
  }

  /// Whether the light sets `setIDs` of `inventory` split (a run scoped to them, card 0121),
  /// without building the scoped inventory.
  package static func splits(_ inventory: Inventory, setIDs: some Sequence<String>) -> Bool {
    laneKinds(in: inventory, setIDs: setIDs).count > 1
  }

  /// The lane kinds the light sets `setIDs` of `inventory` would stack in, in `FilterSet` order:
  /// the broadband one and each line clip measured or asserted (the Stacking columns).
  package static func laneKinds(in inventory: Inventory, setIDs: some Sequence<String>)
    -> [FilterSet]
  {
    let verdicts = Set(setIDs.compactMap { inventory.filterSets[$0] }).filter(\.isKnown)
    return FilterSet.allCases.filter(verdicts.contains)
  }

  /// The lane `set` stacks in (`laneFor`): it renames the stack, never the light, so calibration
  /// still matches on the real filter.
  package static func lane(for set: FrameSet, in inventory: Inventory, split: Bool) -> String {
    guard split, let suffix = suffix(of: LightRef(set, in: inventory).filterSet) else {
      return set.key.filter
    }
    return set.key.filter + suffix
  }

  /// The line clip a lane stacks under, `nil` for a plain (broadband or mono) lane: the longest
  /// suffix wins, so a clip whose wire value ends another's cannot take its lanes.
  package static func lineSet(of lane: String) -> FilterSet? {
    FilterSet.allCases.compactMap { set in suffix(of: set).map { (set, $0) } }
      .filter { lane.hasSuffix($0.1) }
      .max { $0.1.count < $1.1.count }?.0
  }

  /// The kind of knobs a lane takes: its line clip, else the broadband lane's.
  package static func laneKind(of lane: String) -> FilterSet {
    lineSet(of: lane) ?? .broadband
  }

  /// The filter the lights were shot with.
  package static func baseFilter(of lane: String) -> String {
    guard let set = lineSet(of: lane), let suffix = suffix(of: set) else { return lane }
    return String(lane.dropLast(suffix.count))
  }

  /// The line-clip lanes among `lanes`, in `FilterSet` order (the dual-band lane first), two
  /// lanes of one clip by name: the same first lane whatever the map's order.
  package static func lineLanes(in lanes: some Sequence<String>) -> [String] {
    let lines = lanes.compactMap { lane in lineSet(of: lane).map { (lane, order(of: $0)) } }
    return lines.sorted { ($0.1, $0.0) < ($1.1, $1.0) }.map(\.0)
  }

  /// A clip's rank in `FilterSet` order.
  private static func order(of set: FilterSet) -> Int {
    FilterSet.allCases.firstIndex(of: set) ?? FilterSet.allCases.count
  }

  /// `ordered` with the line-clip lanes moved last, in set order, so the broadband master is the
  /// registration reference and defines the canvas (the port's `dualbandLast`).
  package static func lineLanesLast(_ ordered: [String]) -> [String] {
    let lines = lineLanes(in: ordered)
    return ordered.filter { !lines.contains($0) } + lines
  }
}
