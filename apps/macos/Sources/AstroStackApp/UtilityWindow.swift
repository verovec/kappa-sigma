package import AppKit
internal import RenderKit
package import SwiftUI

/// The app's single-instance utility windows (Settings, Help › Keyboard Shortcuts, Help ›
/// Glossary): one window per id, created the first time, reused after.
package enum UtilityWindow {
  private static var windows: [String: NSWindow] = [:]

  /// Shows the window `id`, titled `title`, its content made by `content` the first time.
  ///
  /// `size`, when given, is the content's size and minimum, its width fixed (Settings): a content
  /// without an intrinsic height (a grouped `Form` scrolls) left to SwiftUI collapses the window
  /// to its title bar (card 0177).
  @discardableResult
  package static func show<Content: View>(
    _ id: String, title: LocalizedStringResource, size: NSSize? = nil,
    content: () -> Content
  ) -> NSWindow {
    let window =
      windows[id] ?? make(title: title, size: size, content: content())
    windows[id] = window
    window.makeKeyAndOrderFront(nil)
    return window
  }

  private static func make<Content: View>(
    title: LocalizedStringResource, size: NSSize?, content: Content
  ) -> NSWindow {
    let hosting = NSHostingController(
      rootView: content.background(DesignColor.surface.color).interfaceLocale())
    // The window holds the size; SwiftUI republishing it on a layout pass is what looped in the
    // project window (card 0176).
    if size != nil { hosting.sizingOptions = [] }
    let window = NSWindow(contentViewController: hosting)
    window.title = String(localized: title)
    window.styleMask = [.titled, .closable, .resizable]
    window.isReleasedWhenClosed = false
    if let size {
      window.setContentSize(size)
      window.contentMinSize = size
      window.contentMaxSize = NSSize(width: size.width, height: .greatestFiniteMagnitude)
    }
    return window
  }
}
