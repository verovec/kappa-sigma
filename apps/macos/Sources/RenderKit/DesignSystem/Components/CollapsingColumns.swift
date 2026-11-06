package import SwiftUI

/// A row of columns that fits any width it is proposed: its subviews are sized by their
/// `.column(_:)` widths and the proposal alone (`ColumnSizing`), never by what they hold.
///
/// A row whose minimum followed its content asked a split view's column for more than the window
/// gave it, and AppKit looped on the constraints until it raised (crashes of 29/10 and 06/11, card
/// 0176). Here the minimum is fixed by the declared widths; a collapsing column shows nothing at
/// zero width, so it takes no click and leaves the accessibility tree.
package struct CollapsingColumns: Layout {
  /// A row of the subviews' columns.
  package init() {}

  package func sizeThatFits(
    proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) -> CGSize {
    let widths = ColumnSizing.widths(Self.columns(subviews), in: proposal.width)
    var height: CGFloat = 0
    for (subview, width) in zip(subviews, widths) where width > 0 {
      let proposed = ProposedViewSize(width: width, height: proposal.height)
      height = max(height, subview.sizeThatFits(proposed).height)
    }
    return CGSize(width: widths.reduce(0, +), height: height)
  }

  package func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    let widths = ColumnSizing.widths(Self.columns(subviews), in: bounds.width)
    // Edges on whole points: dividers stay sharp and the image's drawable size whole.
    var edge: CGFloat = 0
    for (subview, width) in zip(subviews, widths) {
      let start = (bounds.minX + edge).rounded()
      edge += width
      let end = (bounds.minX + edge).rounded()
      subview.place(
        at: CGPoint(x: start, y: bounds.minY), anchor: .topLeading,
        proposal: ProposedViewSize(width: end - start, height: bounds.height))
    }
  }

  /// The subviews' declared widths; one without `.column(_:)` is flexible from zero.
  private static func columns(_ subviews: Subviews) -> [ColumnWidth] {
    subviews.map { $0[ColumnWidthKey.self] }
  }
}

/// The width a subview declares to its `CollapsingColumns` row.
private struct ColumnWidthKey: LayoutValueKey {
  static let defaultValue = ColumnWidth(min: 0, ideal: 0, max: .infinity)
}

extension View {
  /// This view as a column of a `CollapsingColumns` row, `width` wide; it takes the width it is
  /// given (its overflow is clipped), and a collapsing column shows nothing at zero width.
  package func column(_ width: ColumnWidth) -> some View {
    ColumnSlot(width: width) { self }.layoutValue(key: ColumnWidthKey.self, value: width)
  }
}
