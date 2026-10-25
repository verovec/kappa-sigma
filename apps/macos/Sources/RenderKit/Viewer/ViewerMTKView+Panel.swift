package import AppKit
package import Foundation

/// ⌥⌘0 hides or shows the « View » panel (card 0126), from the menu through the responder chain
/// like ⌘0; the menu item says what it will do.
extension ViewerMTKView: NSMenuItemValidation {
  /// Hides the panel when shown, shows it when hidden (View › Hide/Show View Panel).
  @objc package func toggleViewerPanel(_ sender: Any?) {
    // Focused, the image is all there is (card 0127): the panel comes back on exit.
    guard !model.isFocused else { return }
    model.showsPanel.toggle()
  }

  /// A hidden panel takes its focused control with it: the surface takes the keyboard back, so
  /// ⌥⌘0, ⌘0 and ⌘1 keep working without a click on the image.
  func panelToggled() {
    guard !model.showsPanel, let window, window.firstResponder !== self else { return }
    window.makeFirstResponder(self)
  }

  /// The menu title of the panel command: what it does from `showsPanel`; `locale` pins the
  /// language (tests), the user's otherwise.
  package nonisolated static func panelCommandTitle(
    showsPanel: Bool, locale: Locale? = nil
  ) -> LocalizedStringResource {
    showsPanel
      ? .renderKit("Hide View Panel", locale: locale)
      : .renderKit("Show View Panel", locale: locale)
  }

  package func validateMenuItem(_ item: NSMenuItem) -> Bool {
    if item.action == #selector(toggleViewerPanel(_:)) {
      item.title = String(localized: Self.panelCommandTitle(showsPanel: model.showsPanel))
      return !model.isFocused
    } else if item.action == #selector(toggleFocusImage(_:)) {
      item.state = model.isFocused ? .on : .off
    }
    return true
  }
}
