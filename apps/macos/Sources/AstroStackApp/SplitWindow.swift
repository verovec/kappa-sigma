package import AppKit

/// The style of a window whose content is a SwiftUI `NavigationSplitView` (project, legacy run).
///
/// The split view bridges a toolbar into the window and insets its columns by it, assuming the
/// content runs under the title bar as in a SwiftUI window. Without `.fullSizeContentView` AppKit
/// already places the content below the title bar, the inset is counted twice and the top of every
/// pane lands under the toolbar band, blurred (card 0084).
package enum SplitWindow {
  /// Titled, closable, miniaturizable, resizable, content under the title bar.
  package static let styleMask: NSWindow.StyleMask = [
    .titled, .closable, .miniaturizable, .resizable, .fullSizeContentView,
  ]
}
