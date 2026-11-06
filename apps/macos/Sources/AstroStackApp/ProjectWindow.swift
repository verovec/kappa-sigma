package import AppKit

/// The project window: a frame restored from an earlier session, saved by a build with a smaller
/// minimum, never stays under `contentMinSize` — a window narrower than its columns is the layout
/// loop of card 0176.
package final class ProjectWindow: NSWindow {
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
