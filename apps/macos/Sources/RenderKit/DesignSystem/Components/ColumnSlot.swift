internal import SwiftUI

/// A column's content at the width its `CollapsingColumns` row gives it: it takes that width
/// whatever it holds (its overflow is clipped), and a collapsing column builds nothing at zero.
struct ColumnSlot<Content: View>: View {
  let width: ColumnWidth
  @ViewBuilder let content: Content
  /// The row gave this collapsing column no width.
  ///
  /// Its content is then not built, so it takes no click and leaves the accessibility tree. It is
  /// read from the width the row gave, which never depends on the content, so it cannot feed back
  /// into the row's widths.
  @State private var collapsed = false

  var body: some View {
    if width.collapseRank == nil {
      filled
    } else {
      Group {
        if collapsed {
          Color.clear.frame(minWidth: 0, minHeight: 0)
        } else {
          filled
        }
      }
      .onGeometryChange(for: Bool.self) { geometry in
        geometry.size.width <= 0
      } action: { zero in
        collapsed = zero
      }
    }
  }

  private var filled: some View {
    content
      .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .clipped()
  }
}
