/// Card 0127: the zoom steps (⌘= / ⌘-), the focus on the image, the panel shown or hidden, and
/// the view resizes they cause.
extension ViewerModel {
  /// Twice as close, around the view centre (⌘=), within `ViewTransform.scales`.
  package func zoomIn() {
    zoom(by: 2, atView: viewSize / 2)
  }

  /// Twice as far, around the view centre (⌘-), within `ViewTransform.scales`.
  package func zoomOut() {
    zoom(by: 0.5, atView: viewSize / 2)
  }

  /// Shows or hides the panel; `remembered` stores it as the user's choice for the next viewer
  /// (a focus hiding the panel, or a test, is not).
  package func showPanel(_ shown: Bool, remembered: Bool) {
    remembersPanel = remembered
    defer { remembersPanel = true }
    showsPanel = shown
  }

  /// The view is now `size`: a window resize, the panel hidden or shown.
  ///
  /// The image point under the view centre stays there at the same zoom; an image that was whole
  /// and no longer is is fitted again. An empty size (a collapsing layout) is ignored: the next
  /// real one is compared with the last real one. Focused and not zoomed yet, the image fills
  /// each new size (card 0127).
  package func resizeView(to size: SIMD2<Double>) {
    guard size.x > 0, size.y > 0 else { return }
    let old = viewSize
    viewSize = size
    if fitsUntilMoved {
      zoomToFit()
      return
    }
    // `zoomToFit`'s scale times the view can land a hair under the image: compare relatively.
    let whole = { (view: SIMD2<Double>) in
      let shown = view * self.frame.transform.scale * (1 + 1e-9)
      return shown.x >= Double(self.image.width) && shown.y >= Double(self.image.height)
    }
    if whole(old), !whole(size) {
      zoomToFit()
      return
    }
    let transform = frame.transform
    frame.transform = ViewTransform(
      scale: transform.scale, origin: transform.origin + (old - size) / 2 * transform.scale)
  }

  /// Entering focus hides the panel and fits the image until the user zooms; leaving puts the
  /// panel back as it was and keeps the transform (display only, R2).
  func focusChanged() {
    if isFocused {
      panelBeforeFocus = showsPanel
      showPanel(false, remembered: false)
      fitsUntilMoved = true
      zoomToFit()
    } else {
      fitsUntilMoved = false
      showPanel(panelBeforeFocus, remembered: false)
    }
    focusToggled?()
  }
}
