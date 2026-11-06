package import CoreGraphics

/// The widths of a row of columns from the proposed width alone, never from what the columns
/// hold: a minimum that follows the content can loop a split view (card 0176).
package enum ColumnSizing {
  /// The row's minimum: the columns that never collapse, at their minimum.
  package static func minimum(_ columns: [ColumnWidth]) -> CGFloat {
    columns.filter { $0.collapseRank == nil }.map(\.min).reduce(0, +)
  }

  /// Each column's width in `available` (`nil`: the ideal row); a collapsed column is 0.
  ///
  /// Collapsing columns go, lowest rank first, while the shown minimums exceed `available`; the
  /// room left grows every column toward its ideal, then toward its maximum, each in proportion
  /// to its own room.
  package static func widths(_ columns: [ColumnWidth], in available: CGFloat?) -> [CGFloat] {
    guard let available else { return columns.map(\.ideal) }
    guard available.isFinite else {
      return columns.map { $0.max.isFinite ? $0.ideal : .infinity }
    }
    var shown = Array(repeating: true, count: columns.count)
    var needed = columns.map(\.min).reduce(0, +)
    let collapsing = columns.indices.filter { columns[$0].collapseRank != nil }
      .sorted { (columns[$0].collapseRank ?? 0, $0) < (columns[$1].collapseRank ?? 0, $1) }
    for index in collapsing where needed > available {
      needed -= columns[index].min
      shown[index] = false
    }
    // Shown is the collapse decision, never the width: a column may be shown from zero.
    var widths = columns.indices.map { shown[$0] ? columns[$0].min : 0 }
    var room = Swift.max(0, available - needed)
    room = grow(&widths, shown: shown, toward: columns.map(\.ideal), by: room)
    _ = grow(&widths, shown: shown, toward: columns.map(\.max), by: room)
    return widths
  }

  /// Grows the shown `widths` toward `targets` by at most `room`; returns the room not used.
  ///
  /// Each grows in proportion to its distance; an infinite target shares what is left equally.
  private static func grow(
    _ widths: inout [CGFloat], shown: [Bool], toward targets: [CGFloat], by room: CGFloat
  ) -> CGFloat {
    let distances = widths.indices.map { shown[$0] ? Swift.max(0, targets[$0] - widths[$0]) : 0 }
    let unbounded = distances.indices.filter { distances[$0].isInfinite }
    if !unbounded.isEmpty {
      for index in unbounded { widths[index] += room / CGFloat(unbounded.count) }
      return 0
    }
    let total = distances.reduce(0, +)
    guard total > 0, room > 0 else { return room }
    let share = Swift.min(1, room / total)
    for index in widths.indices { widths[index] += distances[index] * share }
    return room - total * share
  }
}
