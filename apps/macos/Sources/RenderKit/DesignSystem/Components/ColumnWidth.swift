package import CoreGraphics

/// How one column of a `CollapsingColumns` row is sized, in points.
package struct ColumnWidth: Equatable, Sendable {
  /// The narrowest the column is shown.
  package var min: CGFloat
  /// Its width when nothing is proposed, and what it grows to before any column passes its own.
  package var ideal: CGFloat
  /// The widest it gets; `.infinity` takes what the others leave.
  package var max: CGFloat
  /// Collapses (shown at zero width) when the row cannot hold every column's minimum; lower ranks
  /// collapse first; `nil` never collapses.
  package var collapseRank: Int?

  /// A column between `min` and `max`, `ideal` when nothing is proposed.
  package init(min: CGFloat, ideal: CGFloat, max: CGFloat, collapseRank: Int? = nil) {
    self.min = min
    self.ideal = ideal
    self.max = max
    self.collapseRank = collapseRank
  }
}
