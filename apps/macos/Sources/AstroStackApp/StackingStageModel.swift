package import FilterKit
internal import Observation
package import StackKit

/// The series a run stacks (card 0095): the light sets of the last scan, grouped object → night,
/// a checkbox each — every set checked by default — and one run per object with a checked set.
///
/// Nothing is picked for the user: two objects imported together are two runs, each visible here
/// before Run (R2). Without a scan the table is empty and a run takes every light of the project.
/// The grouping is `RunScope.scopes(of:)`'s, the one the engine refuses to cross.
@Observable
package final class StackingStageModel {
  /// One light set as the table shows it.
  package struct Series: Identifiable, Equatable, Sendable {
    /// The set id (`SetKey.id`), what the scope records.
    package let id: String
    /// The `OBJECT` of the lights.
    package let object: String
    /// The capture night; `""` when undated or single-night.
    package let night: String
    /// The filter name as the capture wrote it.
    package let filter: String
    /// The lane of a colour set (`dualband` only when the run splits), `unknown` otherwise.
    package let filterSet: FilterSet
    /// The sub-exposure.
    package let exposureMs: Int
    /// The camera gain.
    package let gain: Int
    /// Lights in the set.
    package let frames: Int
    /// The sum of the set's exposures.
    package let integrationMs: Int
  }

  /// The sets of one object on one night.
  package struct Night: Identifiable, Equatable, Sendable {
    /// The object the night belongs to.
    package let object: String
    /// The night key; `""` when undated or single-night.
    package let night: String
    /// Its sets, in the scan's order.
    package let series: [Series]
    /// Unique in the table: the object, then the night.
    package var id: String { object + "|" + night }
  }

  /// The nights of one object.
  package struct Group: Identifiable, Equatable, Sendable {
    /// The object.
    package let object: String
    /// Its nights, undated last.
    package let nights: [Night]
    /// One group per object.
    package var id: String { object }
  }

  /// Objects in name order, each with its nights (undated last) and their sets in scan order.
  package private(set) var groups: [Group] = []
  /// One run per object with a checked set, in the table's order; empty without a scan.
  package private(set) var scopes: [RunScope] = []
  private var checked: Set<String> = []
  /// The last scan, which `splits(_:)` asks the engine about.
  private var inventory: Inventory?
  /// Every set id a scan listed so far: a set seen before keeps its choice, a new one is checked.
  private var seen: Set<String> = []

  /// The series of `inventory` (none for `nil`), every one checked.
  package init(inventory: Inventory?) {
    replace(inventory: inventory)
  }

  /// A new scan: the sets it still has keep their choice, the new ones are checked.
  package func replace(inventory: Inventory?) {
    self.inventory = inventory
    groups = inventory.map(Self.groups(of:)) ?? []
    let ids = Set(groups.flatMap(\.nights).flatMap(\.series).map(\.id))
    // Kept: the choice on a set seen before (a dropped scan in between forgets nothing); new sets
    // start checked. A choice on a set the scan no longer lists waits for it to come back.
    checked.formUnion(ids.filter { !seen.contains($0) })
    seen.formUnion(ids)
    rebuildScopes()
  }

  /// The set is checked: its lights go into its object's run.
  package func isChecked(_ id: String) -> Bool { checked.contains(id) }

  /// Checks or unchecks a set.
  package func set(_ id: String, checked value: Bool) {
    if value { checked.insert(id) } else { checked.remove(id) }
    rebuildScopes()
  }

  /// Flips a set's checkbox.
  package func toggle(_ id: String) {
    set(id, checked: !isChecked(id))
  }

  /// The nights with a checked set, in the table's order: what the next runs redo (card 0100).
  package var checkedNights: [Night] {
    groups.flatMap(\.nights).filter { night in night.series.contains { isChecked($0.id) } }
  }

  /// The lane columns of the Stacking panel (card 0121): broadband and dual-band once a checked
  /// object's series split into both lanes, none otherwise.
  package var laneColumns: [FilterSet] {
    scopes.contains(where: splits) ? [.broadband, .dualband] : []
  }

  /// The run of `scope` stacks a broadband and a dual-band lane: the engine's own split of the
  /// scoped inventory (a measured broadband AND a measured dual-band set), never a guess.
  package func splits(_ scope: RunScope) -> Bool {
    inventory.map { FilterSetLanes.splits($0, setIDs: scope.setIDs) } ?? false
  }

  /// No scan: the table has nothing to show.
  package var isEmpty: Bool { groups.isEmpty }

  private func rebuildScopes() {
    scopes = groups.compactMap { group in
      let listed = group.nights.flatMap(\.series)
      let series = listed.filter { checked.contains($0.id) }
      guard !series.isEmpty else { return nil }
      return RunScope(
        object: group.object, setIDs: series.map(\.id), lights: series.map(\.frames).reduce(0, +),
        listed: listed.map(\.id))
    }
  }

  /// The engine's scopes, each laid out as nights of series.
  private static func groups(of inventory: Inventory) -> [Group] {
    let sets = Dictionary(
      inventory.sets.map { ($0.key.id, $0) }, uniquingKeysWith: { first, _ in first })
    return RunScope.scopes(of: inventory).map { scope in
      // The lane as the scoped run will stack it: splitting is decided per run (R2).
      let lanes = IntegrationSummary.Lanes(inventory.scoped(scope))
      var nights: [String: [Series]] = [:]
      for set in scope.setIDs.compactMap({ sets[$0] }) {
        nights[set.key.session, default: []].append(
          Series(
            id: set.key.id, object: set.key.object, night: set.key.session,
            filter: set.key.filter,
            filterSet: lanes.filterSet(of: set),
            exposureMs: set.key.exposureMs, gain: set.key.gain, frames: set.count,
            integrationMs: set.totalIntegrationMs))
      }
      return Group(
        object: scope.object,
        nights: nights.keys.sorted(by: nightPrecedes).map {
          Night(object: scope.object, night: $0, series: nights[$0] ?? [])
        })
    }
  }

  /// Dated nights in order, undated last.
  private static func nightPrecedes(_ lhs: String, _ rhs: String) -> Bool {
    (lhs.isEmpty ? "~" : lhs) < (rhs.isEmpty ? "~" : rhs)
  }
}
