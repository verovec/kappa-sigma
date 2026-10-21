/// What a capture holds, for the Données stage (0078): the lights per target, filter and night,
/// with the exposures, integration and temperature range of each, and totals.
///
/// Read off the scan only: nothing is estimated. A colour night's clip filter (broadband,
/// dual-band) keeps its lights apart, since they stack in different lanes (0081).
package struct IntegrationSummary: Equatable, Sendable {
  /// The lights of one target and filter on one night.
  package struct Row: Equatable, Sendable, Identifiable {
    /// The target (`OBJECT`); `""` when unnamed.
    package var object: String
    /// The filter name (`L`, `Ha`, `RGB` for one-shot colour…).
    package var filter: String
    /// The clip filter of a colour night; `unknown` for mono or undecided.
    package var filterSet: FilterSet
    /// The night key (`YYYY-MM-DD`); `""` for undated frames.
    package var night: String
    /// Lights in the row.
    package var frames = 0
    /// The distinct sub-exposures, shortest first.
    package var exposuresMs: [Int] = []
    /// The sum of the row's exposures.
    package var integrationMs = 0
    /// Coldest and warmest sensor temperature, °C; `nil` when no frame recorded one.
    package var temperatureC: ClosedRange<Double>?
    /// Target, filter, clip filter and night.
    package var id: String { "\(object)|\(filter)|\(filterSet.rawValue)|\(night)" }
  }

  /// One target and filter (and clip filter) over every night.
  package struct Total: Equatable, Sendable, Identifiable {
    /// The target.
    package var object: String
    /// The filter name.
    package var filter: String
    /// The clip filter of a colour night; `unknown` for mono.
    package var filterSet: FilterSet
    /// Lights over every night.
    package var frames: Int
    /// Integration over every night.
    package var integrationMs: Int
    /// The rows it sums: a total over one row only repeats it.
    package var rows: Int
    /// Target, filter and clip filter.
    package var id: String { "\(object)|\(filter)|\(filterSet.rawValue)" }
  }

  /// Targets, then filters in canonical order, then clip filter, then night (undated last).
  package var rows: [Row]
  /// One per target, filter and clip filter, in the rows' order.
  package var totals: [Total]
  /// Every light.
  package var frames: Int { rows.map(\.frames).reduce(0, +) }
  /// The whole integration.
  package var integrationMs: Int { rows.map(\.integrationMs).reduce(0, +) }
  /// Dated nights with any light.
  package var nights: Int { Set(rows.map(\.night).filter { !$0.isEmpty }).count }
  /// Distinct targets: the pane names them only when there are several.
  package var targets: Int { Set(rows.map(\.object)).count }

  /// The lights of `inventory`, by target, filter and night; every other frame type is left out.
  package static func make(inventory: Inventory) -> Self {
    var rows: [String: Row] = [:]
    for set in inventory.sets where set.key.type == .light {
      // The clip filter the run stacks it under: the set's verdict, else its night's.
      let filterSet = LightRef(set, in: inventory).filterSet
      for frame in set.frames {
        let empty = Row(
          object: set.key.object, filter: set.key.filter, filterSet: filterSet,
          night: frame.session)
        var row = rows[empty.id] ?? empty
        row.add(frame)
        rows[empty.id] = row
      }
    }
    let ordered = rows.values.sorted(by: precedes)
    return Self(rows: ordered, totals: totals(of: ordered))
  }

  private static func precedes(_ lhs: Row, _ rhs: Row) -> Bool {
    if lhs.object != rhs.object { return lhs.object < rhs.object }
    if lhs.filter != rhs.filter { return Filter.less(lhs.filter, rhs.filter) }
    if lhs.filterSet != rhs.filterSet {
      let order = FilterSet.allCases
      return order.firstIndex(of: lhs.filterSet) ?? 0 < order.firstIndex(of: rhs.filterSet) ?? 0
    }
    // Undated frames sort after every night.
    return (lhs.night.isEmpty ? "~" : lhs.night) < (rhs.night.isEmpty ? "~" : rhs.night)
  }

  private static func totals(of rows: [Row]) -> [Total] {
    var totals: [Total] = []
    for row in rows {
      if let last = totals.last, last.object == row.object, last.filter == row.filter,
        last.filterSet == row.filterSet
      {
        totals[totals.count - 1].frames += row.frames
        totals[totals.count - 1].integrationMs += row.integrationMs
        totals[totals.count - 1].rows += 1
      } else {
        totals.append(
          Total(
            object: row.object, filter: row.filter, filterSet: row.filterSet, frames: row.frames,
            integrationMs: row.integrationMs, rows: 1))
      }
    }
    return totals
  }
}

extension IntegrationSummary.Row {
  fileprivate mutating func add(_ frame: CaptureFrame) {
    frames += 1
    integrationMs += frame.exposureMs
    if !exposuresMs.contains(frame.exposureMs) {
      exposuresMs.append(frame.exposureMs)
      exposuresMs.sort()
    }
    guard frame.hasTemp else { return }
    let celsius = Double(frame.tempMilliC) / 1000
    temperatureC =
      temperatureC.map { min($0.lowerBound, celsius)...max($0.upperBound, celsius) }
      ?? celsius...celsius
  }
}
