/// What a capture holds, for the Données stage (0078): the lights per filter × night, with the
/// exposures, integration and temperature range of each, and totals.
///
/// Read off the scan only: nothing is estimated. A colour night's clip filter (broadband,
/// dual-band) keeps its lights apart, since they stack in different lanes (0081).
package struct IntegrationSummary: Equatable, Sendable {
  /// The lights of one filter on one night.
  package struct Row: Equatable, Sendable, Identifiable {
    /// The filter name (`L`, `Ha`, `RGB` for one-shot colour…).
    package var filter: String
    /// The clip filter of a colour night; `unknown` for mono or undecided.
    package var filterSet: FilterSet
    /// The night key (`YYYY-MM-DD`); `""` for undated frames.
    package var night: String
    package var frames: Int
    /// The distinct sub-exposures, shortest first.
    package var exposuresMs: [Int]
    package var integrationMs: Int
    /// Coldest and warmest sensor temperature, °C; `nil` when no frame recorded one.
    package var temperatureC: ClosedRange<Double>?
    package var id: String { "\(filter)|\(filterSet.rawValue)|\(night)" }
  }

  /// One filter (and clip filter) over every night.
  package struct Total: Equatable, Sendable, Identifiable {
    package var filter: String
    package var filterSet: FilterSet
    package var frames: Int
    package var integrationMs: Int
    /// Dated nights with lights of this filter.
    package var nights: Int
    package var id: String { "\(filter)|\(filterSet.rawValue)" }
  }

  /// Filters in canonical order, then clip filter, then night (undated last).
  package var rows: [Row]
  /// One per filter and clip filter, in the rows' order.
  package var totals: [Total]
  package var frames: Int { rows.map(\.frames).reduce(0, +) }
  package var integrationMs: Int { rows.map(\.integrationMs).reduce(0, +) }
  /// Dated nights with any light.
  package var nights: Int { Set(rows.map(\.night).filter { !$0.isEmpty }).count }

  /// The lights of `inventory`, by filter × night; every other frame type is left out.
  package static func make(inventory: Inventory) -> Self {
    var rows: [String: Row] = [:]
    for set in inventory.sets where set.key.type == .light {
      for frame in set.frames {
        let id = "\(set.key.filter)|\(set.filterSet.rawValue)|\(frame.session)"
        var row =
          rows[id]
          ?? Row(
            filter: set.key.filter, filterSet: set.filterSet, night: frame.session, frames: 0,
            exposuresMs: [], integrationMs: 0, temperatureC: nil)
        row.add(frame)
        rows[id] = row
      }
    }
    let ordered = rows.values.sorted(by: precedes)
    return Self(rows: ordered, totals: totals(of: ordered))
  }

  private static func precedes(_ lhs: Row, _ rhs: Row) -> Bool {
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
      if let last = totals.last, last.filter == row.filter, last.filterSet == row.filterSet {
        totals[totals.count - 1].frames += row.frames
        totals[totals.count - 1].integrationMs += row.integrationMs
        totals[totals.count - 1].nights += row.night.isEmpty ? 0 : 1
      } else {
        totals.append(
          Total(
            filter: row.filter, filterSet: row.filterSet, frames: row.frames,
            integrationMs: row.integrationMs, nights: row.night.isEmpty ? 0 : 1))
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
    temperatureC = temperatureC.map { min($0.lowerBound, celsius)...max($0.upperBound, celsius) }
      ?? celsius...celsius
  }
}
