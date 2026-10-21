package import AppKit
internal import RenderKit
package import SwiftUI

/// The app's single-instance utility windows (Help › Keyboard Shortcuts, Help › Glossary): one
/// window per id, created the first time, reused after.
package enum UtilityWindow {
  private static var windows: [String: NSWindow] = [:]

  /// Shows the window `id`, titled `title`, its content made by `content` the first time;
  /// `resizable` false for a fixed-size panel (Settings).
  @discardableResult
  package static func show<Content: View>(
    _ id: String, title: LocalizedStringResource, resizable: Bool = true,
    content: () -> Content
  ) -> NSWindow {
    let window = windows[id] ?? make(title: title, resizable: resizable, content: content())
    windows[id] = window
    window.makeKeyAndOrderFront(nil)
    return window
  }

  private static func make<Content: View>(
    title: LocalizedStringResource, resizable: Bool, content: Content
  ) -> NSWindow {
    let window = NSWindow(
      contentViewController: NSHostingController(
        rootView: content.background(DesignColor.surface.color).interfaceLocale()))
    window.title = String(localized: title)
    window.styleMask = resizable ? [.titled, .closable, .resizable] : [.titled, .closable]
    window.isReleasedWhenClosed = false
    return window
  }
}
