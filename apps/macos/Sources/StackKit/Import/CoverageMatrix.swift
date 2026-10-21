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
    package var cells: [ImportPlan.Cell] { channel.cells }
    package var notes: [String] { channel.notes }
    package var hasGap: Bool { channel.hasGap }
    package var id: String { channel.id }
  }

  /// Nights in order (undated last), then filters in canonical order.
  package var rows: [Row]
  /// Light sets with a role nothing covers that the user did not ask to skip.
  package var gaps: Int { rows.filter(\.hasGap).count }

  /// The coverage `plan` describes.
  package init(plan: ImportPlan) {
    let sets = Dictionary(
      plan.inventory.sets.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    rows = plan.calibration.map { channel in
      let set = sets[channel.key]
      // A single-night scan keeps no night in its keys: the frames carry it.
      let night =
        channel.key.session.isEmpty ? set?.frames.first?.session ?? "" : channel.key.session
      return Row(channel: channel, night: night, filterSet: set?.filterSet ?? .unknown)
    }
    .sorted { lhs, rhs in
      let (left, right) = (lhs.night.isEmpty ? "~" : lhs.night, rhs.night.isEmpty ? "~" : rhs.night)
      return left != right ? left < right : Filter.less(lhs.channel.filter, rhs.channel.filter)
    }
  }
}
