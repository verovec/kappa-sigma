package import AppKit

/// Card 0127: ⌘= / ⌘- zoom around the centre, ⇧⌘F shows only the image (full screen), Esc
/// leaves it.
extension ViewerMTKView {
  /// Twice as close (View › Zoom In).
  @objc package func zoomIn(_ sender: Any?) { model.zoomIn() }

  /// Twice as far (View › Zoom Out).
  @objc package func zoomOut(_ sender: Any?) { model.zoomOut() }

  /// Only the image, or back to the columns (View › Full-Screen Image).
  @objc package func toggleFocusImage(_ sender: Any?) { model.isFocused.toggle() }

  /// Esc leaves the focus; otherwise it goes on up the responder chain (a sheet, a field), with
  /// AppKit's beep when nothing takes it.
  override package func cancelOperation(_ sender: Any?) {
    guard model.isFocused else {
      let selector = #selector(cancelOperation(_:))
      if nextResponder?.tryToPerform(selector, with: sender) != true { noResponder(for: selector) }
      return
    }
    model.isFocused = false
  }

  /// The Esc key itself: a plain view gets no `cancelOperation(_:)` from it.
  override package func keyDown(with event: NSEvent) {
    guard event.keyCode == Self.escapeKey, model.isFocused else {
      super.keyDown(with: event)
      return
    }
    model.isFocused = false
  }

  /// Leaving the window (another stage, another stack, the document closed) leaves the focus and
  /// the full screen it entered: nothing else could answer ⇧⌘F or Esc any more.
  override package func viewWillMove(toWindow newWindow: NSWindow?) {
    super.viewWillMove(toWindow: newWindow)
    if newWindow == nil, model.isFocused { model.isFocused = false }
  }

  /// The user left the full screen themselves: it is no longer the focus's to leave.
  @objc func windowExitedFullScreen(_ note: Notification) {
    enteredFullScreen = false
  }

  /// Focus enters the window's full screen unless it is already there, and leaves only the full
  /// screen it entered.
  func focusToggled() {
    guard let window else { return }
    if model.isFocused {
      window.makeFirstResponder(self)
      guard !fullScreen.isOn(window) else { return }
      enteredFullScreen = true
      fullScreen.toggle(window)
    } else {
      defer { enteredFullScreen = false }
      if enteredFullScreen, fullScreen.isOn(window) { fullScreen.toggle(window) }
    }
  }
}
