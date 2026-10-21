/// The calibration coverage of a capture, for the Données stage (0078): each light set's dark,
/// flat and bias exactly as `ImportPlan` (the matcher) decided them, under its night.
///
/// A projection, not a second rule (R2): the cells and notes are the plan's; this adds the night
/// and clip filter of each set, an order to read them in, and the count the journey shows.
package struct CoverageMatrix: Equatable, Sendable {
  /// One light set and its calibration.
  package struct Row: Equatable, Sendable, Identifiable {
    /// The plan's channel: its key, its dark/flat/bias cells and the matcher's notes.
    package var channel: ImportPlan.Channel
    /// The capture night (`YYYY-MM-DD`); `""` when undated.
    package var night: String
    /// The clip filter of a colour light set; `unknown` otherwise.
    package var filterSet: FilterSet
    /// Dark, flat and bias, in that order.
    package var cells: [ImportPlan.Cell] { channel.cells }
    /// The matcher's explanation of every fallback and gap, verbatim.
    package var notes: [String] { channel.notes }
    /// A role nothing covers that the user did not ask to skip.
    package var hasGap: Bool { channel.hasGap }
    /// The light set's id.
    package var id: String { channel.id }
  }

  /// Nights in order (undated last), then filters in canonical order, clip filter, set id.
  package var rows: [Row]
  /// Light sets with a role nothing covers that the user did not ask to skip.
  package var gaps: Int { rows.filter(\.hasGap).count }

  /// The coverage `plan` describes.
  package init(plan: ImportPlan) {
    let sets = Dictionary(
      plan.inventory.sets.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    rows = plan.calibration.map { channel in
      let set = sets[channel.key]
      return Row(
        channel: channel, night: set.map(ImportPlan.night(of:)) ?? channel.key.session,
        filterSet: set?.filterSet ?? .unknown)
    }
    .sorted(by: Self.precedes)
  }

  private static func precedes(_ lhs: Row, _ rhs: Row) -> Bool {
    let (left, right) = (lhs.night.isEmpty ? "~" : lhs.night, rhs.night.isEmpty ? "~" : rhs.night)
    if left != right { return left < right }
    if lhs.channel.filter != rhs.channel.filter {
      return Filter.less(lhs.channel.filter, rhs.channel.filter)
    }
    if lhs.filterSet != rhs.filterSet {
      let order = FilterSet.allCases
      return order.firstIndex(of: lhs.filterSet) ?? 0 < order.firstIndex(of: rhs.filterSet) ?? 0
    }
    return lhs.id < rhs.id
  }
}
