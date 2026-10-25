package import AppKit

/// How the surface reads and toggles its window's full screen (card 0127): the window itself in
/// the app, a recorder in tests (an offscreen window cannot go full screen).
@MainActor
package struct ViewerFullScreen {
  /// The window is in full screen.
  package var isOn: (NSWindow) -> Bool
  /// Enters or leaves it.
  package var toggle: (NSWindow) -> Void

  /// A seam over `isOn` and `toggle`.
  package init(isOn: @escaping (NSWindow) -> Bool, toggle: @escaping (NSWindow) -> Void) {
    self.isOn = isOn
    self.toggle = toggle
  }

  /// The window's own: its style mask, `toggleFullScreen(_:)`.
  package static let window = Self(
    isOn: { $0.styleMask.contains(.fullScreen) }, toggle: { $0.toggleFullScreen(nil) })
}
