package import AppKit

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
}
