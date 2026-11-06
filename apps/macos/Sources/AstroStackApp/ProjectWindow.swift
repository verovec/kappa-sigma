package import AppKit
internal import SwiftUI

/// The project window: a frame restored from an earlier session, saved by a build with a smaller
/// minimum, never stays under `contentMinSize` — a window narrower than its columns is the layout
/// loop of card 0176.
package final class ProjectWindow: NSWindow {
  /// A window over `model` at the opening size: it keeps its own frame and a fixed minimum,
  /// SwiftUI sizes nothing (`SplitWindow`).
  package static func make(model: ProjectWindowModel, projects: ProjectSwitcher.Source)
    -> ProjectWindow
  {
    let window = ProjectWindow(
      contentRect: SplitWindow.contentRect(panes: SplitWindow.openingPanes),
      styleMask: SplitWindow.styleMask, backing: .buffered, defer: false)
    // Swift owns the window (its controller, or a test): closing must not release it again.
    window.isReleasedWhenClosed = false
    let content = NSHostingView(
      rootView: ProjectWindowView(model: model, projects: projects).interfaceLocale())
    // SwiftUI never publishes a size to the window: the minimum is set once, below, holding every
    // column (card 0176 — a republished minimum looped AppKit's constraint passes).
    content.sizingOptions = []
    window.contentView = content
    window.contentMinSize = SplitWindow.contentMinSize
    return window
  }

  override package func restoreState(with coder: NSCoder) {
    super.restoreState(with: coder)
    growToMinimum()
  }

  /// Grows the content to `contentMinSize` where it is smaller (`setFrame` does not enforce it).
  package func growToMinimum() {
    let content = contentRect(forFrameRect: frame).size
    let clamped = SplitWindow.clamped(content, to: contentMinSize)
    if clamped != content { setContentSize(clamped) }
  }
}
