package import AppKit
internal import RenderKit
internal import SwiftUI

/// Window › Component Gallery (debug builds): every shared component in every state, to check a
/// panel against the design system in the running app's appearance and language.
package enum ComponentGalleryWindow {
  private static var window: NSWindow?

  /// Shows the gallery, creating its window the first time.
  @discardableResult
  package static func show() -> NSWindow {
    let window = window ?? make()
    Self.window = window
    window.makeKeyAndOrderFront(nil)
    return window
  }

  private static func make() -> NSWindow {
    let window = NSWindow(
      contentViewController: NSHostingController(
        rootView: ScrollView { ComponentGallery() }
          .background(DesignColor.surface.color)
          .frame(minWidth: 520, minHeight: 480)
          .interfaceLocale()))
    window.title = String(localized: .app("Component Gallery"))
    window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
    window.setContentSize(NSSize(width: 760, height: 820))
    window.isReleasedWhenClosed = false
    return window
  }
}
