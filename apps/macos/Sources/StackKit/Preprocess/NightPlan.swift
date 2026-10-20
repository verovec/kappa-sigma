/// Which nights feed which channel, and the night that pins every channel's canvas
/// (`ReusePlan.computeAnchor`, `anchorGroupIndex`).
///
/// A channel's groups are its light sets, one per night (and setup), in the legacy order. A run
/// is anchored when some channel has two or more; the anchor night is the one covering the most
/// channels, then with the most frames, then the latest. This run's own capture is the only
/// source here, so every group is "current".
package struct NightPlan: Equatable, Sendable {
  /// Channel (lane) → its groups.
  package var channels: [String: [FrameSet]]
  /// Some channel merges several groups.
  package var anchored: Bool
  /// The night every channel's registration canvas is pinned to; empty when not anchored.
  package var anchorNight: String
  /// The dated nights, sorted.
  package var nights: [String]

  /// The plan of `lights` grouped by `lane` (the filter, or a filter-set lane).
  package init(_ lights: [FrameSet], lane: (FrameSet) -> String = \.key.filter) {
    var channels: [String: [FrameSet]] = [:]
    for set in lights { channels[lane(set), default: []].append(set) }
    self.channels = channels.mapValues { groups in
      groups.sorted {
        ($0.key.session, $0.key.exposureMs, $0.key.gain) < (
          $1.key.session, $1.key.exposureMs, $1.key.gain
        )
      }
    }
    anchored = channels.values.contains { $0.count > 1 }
    nights = Set(lights.map(\.key.session)).filter { !$0.isEmpty }.sorted()
    anchorNight = anchored ? Self.anchorNight(self.channels) : ""
  }

  /// The night covering the most channels, then with the most frames, then the latest.
  static func anchorNight(_ channels: [String: [FrameSet]]) -> String {
    var filters: [String: Set<String>] = [:]
    var frames: [String: Int] = [:]
    for (lane, groups) in channels {
      for group in groups {
        filters[group.key.session, default: []].insert(lane)
        frames[group.key.session, default: 0] += group.count
      }
    }
    return filters.keys.max { lhs, rhs in
      let (left, right) = (
        (filters[lhs]?.count ?? 0, frames[lhs] ?? 0), (filters[rhs]?.count ?? 0, frames[rhs] ?? 0)
      )
      return left != right ? left < right : lhs < rhs
    } ?? ""
  }

  /// A channel's anchor group: on the anchor night, then the most frames, then the latest night.
  package static func anchorGroup(_ groups: [FrameSet], anchorNight: String) -> Int {
    var best = 0
    for index in groups.indices.dropFirst() where outranks(groups[index], groups[best], anchorNight)
    {
      best = index
    }
    return best
  }

  private static func outranks(_ challenger: FrameSet, _ incumbent: FrameSet, _ night: String)
    -> Bool
  {
    let (on, incumbentOn) = (challenger.key.session == night, incumbent.key.session == night)
    if on != incumbentOn { return on }
    if challenger.count != incumbent.count { return challenger.count > incumbent.count }
    return challenger.key.session > incumbent.key.session
  }
}
