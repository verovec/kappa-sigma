internal import Observation
package import StackKit

/// The series a run stacks (card 0095): the light sets of the last scan, grouped object → night,
/// a checkbox each — every set checked by default — and one run per object with a checked set.
///
/// Nothing is picked for the user: two objects imported together are two runs, each visible here
/// before Run (R2). Without a scan the table is empty and a run takes every light of the project.
@Observable
package final class StackingStageModel {
  /// One light set as the table shows it.
  package struct Series: Identifiable, Equatable, Sendable {
    /// The set id (`SetKey.id`), what the scope records.
    package let id: String
    package let object: String
    /// The capture night; `""` when undated or single-night.
    package let night: String
    package let filter: String
    /// The lane of a colour set (`dualband` only when the run splits), `unknown` otherwise.
    package let filterSet: FilterSet
    package let exposureMs: Int
    package let gain: Int
    package let frames: Int
    package let integrationMs: Int
  }

  /// The sets of one object on one night.
  package struct Night: Identifiable, Equatable, Sendable {
    package let object: String
    package let night: String
    package let series: [Series]
    package var id: String { object + "|" + night }
  }

  /// The nights of one object.
  package struct Group: Identifiable, Equatable, Sendable {
    package let object: String
    package let nights: [Night]
    package var id: String { object }
  }

  /// Objects in name order, each with its nights (undated last) and their sets in scan order.
  package private(set) var groups: [Group] = []
  private var checked: Set<String> = []

  /// The series of `inventory` (none for `nil`), every one checked.
  package init(inventory: Inventory?) {
    replace(inventory: inventory)
  }

  /// A new scan: the sets it still has keep their choice, the new ones are checked.
  package func replace(inventory: Inventory?) {
    guard let inventory else {
      groups = []
      checked = []
      return
    }
    let split = FilterSetLanes.splits(inventory)
    var byObject: [String: [String: [Series]]] = [:]
    for set in inventory.sets where set.key.type == .light {
      let lane = FilterSetLanes.lane(for: set, in: inventory, split: split)
      let series = Series(
        id: set.key.id, object: set.key.object, night: set.key.session, filter: set.key.filter,
        filterSet: FilterSetLanes.baseFilter(of: lane) == lane ? .unknown : .dualband,
        exposureMs: set.key.exposureMs, gain: set.key.gain, frames: set.count,
        integrationMs: set.totalIntegrationMs)
      byObject[set.key.object, default: [:]][set.key.session, default: []].append(series)
    }
    let known = Set(groups.flatMap(\.nights).flatMap(\.series).map(\.id))
    groups = byObject.keys.sorted().map { object in
      let nights = byObject[object] ?? [:]
      return Group(
        object: object,
        nights: nights.keys.sorted(by: Self.nightPrecedes).map {
          Night(object: object, night: $0, series: nights[$0] ?? [])
        })
    }
    let ids = Set(groups.flatMap(\.nights).flatMap(\.series).map(\.id))
    // Kept: the choice on a set the new scan still has; new sets start checked.
    checked = ids.filter { !known.contains($0) || checked.contains($0) }
  }

  /// The set is checked: its lights go into its object's run.
  package func isChecked(_ id: String) -> Bool { checked.contains(id) }

  /// Checks or unchecks a set.
  package func set(_ id: String, checked value: Bool) {
    if value { checked.insert(id) } else { checked.remove(id) }
  }

  /// Flips a set's checkbox.
  package func toggle(_ id: String) {
    set(id, checked: !isChecked(id))
  }

  /// No scan: the table has nothing to show.
  package var isEmpty: Bool { groups.isEmpty }

  /// One run per object with a checked set, in the table's order; empty without a scan.
  package var scopes: [RunScope] {
    groups.compactMap { group in
      let series = group.nights.flatMap(\.series).filter { checked.contains($0.id) }
      guard !series.isEmpty else { return nil }
      return RunScope(
        object: group.object, setIDs: series.map(\.id), lights: series.map(\.frames).reduce(0, +))
    }
  }

  /// Dated nights in order, undated last.
  private static func nightPrecedes(_ lhs: String, _ rhs: String) -> Bool {
    (lhs.isEmpty ? "~" : lhs) < (rhs.isEmpty ? "~" : rhs)
  }
}
