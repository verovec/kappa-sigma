package import AppKit
package import RenderKit

/// The style of a window whose content is a SwiftUI `NavigationSplitView` (project, legacy run).
///
/// The split view bridges a toolbar into the window and insets its columns by it, assuming the
/// content runs under the title bar as in a SwiftUI window. Without `.fullSizeContentView` AppKit
/// already places the content below the title bar, the inset is counted twice and the top of every
/// pane lands under the toolbar band, blurred (card 0084). The content rect then includes the
/// title bar: `contentRect(panes:)` adds it. `PaneInsetTests` pins the layout.
package enum SplitWindow {
  /// Titled, closable, miniaturizable, resizable, content under the title bar.
  package static let styleMask: NSWindow.StyleMask = [
    .titled, .closable, .miniaturizable, .resizable, .fullSizeContentView,
  ]

  /// The unified title bar with the split view's bridged toolbar (macOS 26), in points.
  package static let titleBarHeight: CGFloat = 52

  /// The content rect of a window whose panes get `panes` below the title bar.
  package static func contentRect(panes: NSSize) -> NSRect {
    NSRect(x: 0, y: 0, width: panes.width, height: panes.height + titleBarHeight)
  }

  /// The journey sidebar's column.
  package static let sidebarWidth = ColumnWidth(min: 180, ideal: 210, max: 280)
  /// The first-stack guide's column, beside the detail when the guide is open.
  package static let guideWidth = ColumnWidth(min: 220, ideal: 260, max: 340)
  /// The split view's dividers between those columns.
  package static let dividers: CGFloat = 2
  /// What every stage's pane fits in, in every state.
  package static let detailMinSize = NSSize(width: 720, height: 400)
  /// The panes a project window opens with: wide enough for the Studio's View panel beside the
  /// image with the sidebar at its ideal (`StagePaneMinimumTests`).
  package static let openingPanes = NSSize(width: 1400, height: 800)

  /// The smallest panes of a project window, below the title bar: every column at its minimum,
  /// the guide's included, so no column is ever asked for a width the window cannot give.
  package static var minPanes: NSSize {
    NSSize(
      width: sidebarWidth.min + detailMinSize.width + guideWidth.min + dividers,
      height: detailMinSize.height)
  }

  /// The project window's minimum content size, set once on the window.
  ///
  /// Left to the hosting view (`sizingOptions = [.minSize]`) it was published again on every
  /// layout pass. A column cannot republish one either: a pane wider than the detail column made
  /// the split view's column ask for a minimum the window could not give, and AppKit looped until
  /// it raised « more Update Constraints in Window passes than there are views » (29/10 and 06/11
  /// crashes, card 0176) — so every pane fits `detailMinSize` (`StagePaneMinimumTests`).
  package static var contentMinSize: NSSize { contentRect(panes: minPanes).size }

  /// `size` grown to `minimum` in each dimension where it is smaller.
  package static func clamped(_ size: NSSize, to minimum: NSSize) -> NSSize {
    NSSize(width: max(size.width, minimum.width), height: max(size.height, minimum.height))
  }
}
