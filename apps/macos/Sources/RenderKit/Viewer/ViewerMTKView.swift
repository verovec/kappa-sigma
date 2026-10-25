package import AppKit
package import MetalKit
internal import os

/// The Metal surface of the viewer: draws `model.frame` on demand and turns events into model
/// changes — scroll/pinch zoom around the cursor, drag with the current tool, ⌥ held to compare,
/// ⌘0 / ⌘1 / ⌥⌘0 / ⌘= / ⌘- / ⇧⌘F / Esc through the responder chain (`zoomToFit(_:)`,
/// `zoomToActualSize(_:)`, `toggleViewerPanel(_:)`, `zoomIn(_:)`, `zoomOut(_:)`,
/// `toggleFocusImage(_:)`, `cancelOperation(_:)`).
@MainActor
package final class ViewerMTKView: MTKView, MTKViewDelegate {
  private nonisolated static let logger = Logger(
    subsystem: "fr.astrostack", category: "RenderKit/viewer")
  private nonisolated static let signposter = OSSignposter(logger: logger)

  let model: ViewerModel
  private let renderer: ViewerRenderer
  /// The image drawn.
  package private(set) var texture: ImageTexture
  /// What the compare key and split show (the current image when `nil`).
  package private(set) var reference: ImageTexture?
  /// The process mask the Studio shows with `ViewerFrame.maskOverlay` (one plane, image size).
  package private(set) var mask: MTLTexture?
  private var dragStart: SIMD2<Double>?
  private var dragLast: SIMD2<Double>?
  private var fitted = false
  /// How focus enters and leaves the window's full screen (card 0127).
  package var fullScreen = ViewerFullScreen.window
  /// Focus entered the window's full screen: leaving focus leaves it (never the user's own).
  var enteredFullScreen = false
  /// The Esc key's virtual key code.
  static let escapeKey: UInt16 = 53
  /// The backing scale the drawable size was last given at.
  private var backing: CGFloat?
  /// What the shown histogram counted (`nil`: nothing counted yet).
  private var counted: ViewerFrame.HistogramInput?
  private var frameNumber = 0
  /// The newest histogram buffer: read on the main actor once its frame completes.
  private var pendingBins: (frame: Int, bins: MTLBuffer)?

  /// A surface drawing `texture` (and `reference` for compare) with `renderer`, driven by `model`.
  package init(
    model: ViewerModel, renderer: ViewerRenderer, texture: ImageTexture, reference: ImageTexture?,
    mask: MTLTexture? = nil
  ) {
    self.model = model
    self.renderer = renderer
    self.texture = texture
    self.reference = reference
    self.mask = mask
    super.init(frame: .zero, device: renderer.device)
    delegate = self
    colorPixelFormat = .bgra8Unorm
    framebufferOnly = false
    isPaused = true
    enableSetNeedsDisplay = true
    model.redraw = { [weak self] in self?.needsDisplay = true }
    model.panelToggled = { [weak self] in self?.panelToggled() }
    model.focusToggled = { [weak self] in self?.focusToggled() }
  }

  /// Draws these inputs from now on (SwiftUI hands them on every update: the Studio swaps the
  /// texture on each preview, Apply and undo); whether any changed.
  @discardableResult
  package func show(texture: ImageTexture, reference: ImageTexture?, mask: MTLTexture?) -> Bool {
    guard texture !== self.texture || reference !== self.reference || mask !== self.mask else {
      return false
    }
    if texture !== self.texture {
      // The histogram counted the image drawn so far: count the new one.
      counted = nil
      pendingBins = nil
    }
    self.texture = texture
    self.reference = reference
    self.mask = mask
    needsDisplay = true
    return true
  }

  @available(*, unavailable)
  required init(coder: NSCoder) {
    preconditionFailure("ViewerMTKView is created in code")
  }

  override package var isFlipped: Bool { true }
  override package var acceptsFirstResponder: Bool { true }

  /// Takes the keyboard (⌥, ⌘0, ⌘1 work before any click) and drops the compare key when the
  /// window stops being key — the ⌥ release then goes to another app.
  override package func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    let center = NotificationCenter.default
    center.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
    center.removeObserver(self, name: NSWindow.didExitFullScreenNotification, object: nil)
    guard let window else { return }
    window.makeFirstResponder(self)
    center.addObserver(
      self, selector: #selector(windowResignedKey), name: NSWindow.didResignKeyNotification,
      object: window)
    center.addObserver(
      self, selector: #selector(windowExitedFullScreen),
      name: NSWindow.didExitFullScreenNotification, object: window)
  }

  @objc private func windowResignedKey(_ note: Notification) {
    model.compareKeyHeld = false
  }

  override package func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(
      NSTrackingArea(
        rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self))
  }

  // MARK: - Drawing

  /// The canvas grey follows the appearance: draw again when it changes.
  override package func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }

  package func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    let size = SIMD2(Double(size.width), Double(size.height))
    guard fitted else {
      model.viewSize = size
      if size.x > 0, size.y > 0 {
        fitted = true
        model.zoomToFit()
      }
      return
    }
    let scale = window?.backingScaleFactor
    defer { backing = scale }
    guard backing == nil || scale == backing else {
      // Another display's backing scale: the same view in points, nothing to keep centred.
      model.viewSize = size
      return
    }
    // The panel hidden or shown, a window resize: keep where the user looks (card 0126).
    model.resizeView(to: size)
  }

  package func draw(in view: MTKView) {
    guard let drawable = currentDrawable, let commands = renderer.queue.makeCommandBuffer() else {
      return
    }
    var frame = model.frame
    frame.canvasGrey = DesignColor.canvasGrey(in: DesignAppearance(effectiveAppearance))
    // The histogram depends on the image, the region and (display domain) the stretch only:
    // count again when they change.
    let counting = counted != frame.histogramInput
    let interval = Self.signposter.beginInterval("frame", id: Self.signposter.makeSignpostID())
    do {
      let bins = try renderer.encode(
        into: commands, image: texture, reference: reference, frame: frame,
        output: drawable.texture, histogram: counting, mask: mask)
      frameNumber += 1
      let number = frameNumber
      if let bins {
        counted = frame.histogramInput
        pendingBins = (number, bins)
      }
      commands.addCompletedHandler { [weak self] _ in
        Self.signposter.endInterval("frame", interval)
        Task { @MainActor in self?.frameCompleted(number) }
      }
    } catch {
      Self.signposter.endInterval("frame", interval)
      Self.logger.error("frame not drawn: \(String(describing: error), privacy: .public)")
      return
    }
    commands.present(drawable)
    commands.commit()
  }

  private func frameCompleted(_ frame: Int) {
    guard let pending = pendingBins, pending.frame == frame else { return }
    pendingBins = nil
    model.histogram = Histogram.counts(pending.bins, channels: texture.planes.count)
    let counted = model.histogram.first?.reduce(0, +) ?? 0
    Self.logger.info("histogram counted: \(counted, privacy: .public) pixels per channel")
  }

  // MARK: - Events

  override package func scrollWheel(with event: NSEvent) {
    let step = event.hasPreciseScrollingDeltas ? 0.01 : 0.1
    model.zoom(by: exp(Double(event.scrollingDeltaY) * step), atView: viewPoint(event))
  }

  override package func magnify(with event: NSEvent) {
    model.zoom(by: 1 + Double(event.magnification), atView: viewPoint(event))
  }

  override package func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    let point = viewPoint(event)
    if event.clickCount == 2, model.tool == .region {
      model.clearRegion()
    }
    dragStart = point
    dragLast = point
  }

  override package func mouseDragged(with event: NSEvent) {
    guard let start = dragStart, let last = dragLast else { return }
    let point = viewPoint(event)
    model.drag(from: model.tool == .pan ? last : start, to: point, tool: model.tool)
    dragLast = point
    model.hover(atView: point)
  }

  override package func mouseUp(with event: NSEvent) {
    dragStart = nil
    dragLast = nil
  }

  override package func mouseMoved(with event: NSEvent) {
    model.hover(atView: viewPoint(event))
  }

  override package func flagsChanged(with event: NSEvent) {
    model.compareKeyHeld = event.modifierFlags.contains(.option)
  }

  @objc package func zoomToFit(_ sender: Any?) { model.zoomToFit() }
  @objc package func zoomToActualSize(_ sender: Any?) { model.zoomToActualSize() }

  /// The event's location in drawable pixels, top-left origin.
  private func viewPoint(_ event: NSEvent) -> SIMD2<Double> {
    let point = convert(event.locationInWindow, from: nil)
    let backing = Double(window?.backingScaleFactor ?? 1)
    return SIMD2(Double(point.x), Double(point.y)) * backing
  }
}
