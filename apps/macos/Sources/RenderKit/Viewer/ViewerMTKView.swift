internal import AppKit
internal import MetalKit
internal import os

/// The Metal surface of the viewer: draws `model.frame` on demand and turns events into model
/// changes — scroll/pinch zoom around the cursor, drag with the current tool, ⌥ held to compare,
/// ⌘0 / ⌘1 through the responder chain (`zoomToFit(_:)`, `zoomToActualSize(_:)`).
@MainActor
final class ViewerMTKView: MTKView, MTKViewDelegate {
  private nonisolated static let logger = Logger(
    subsystem: "fr.astrostack", category: "RenderKit/viewer")
  private nonisolated static let signposter = OSSignposter(logger: logger)

  private let model: ViewerModel
  private let renderer: ViewerRenderer
  private let texture: ImageTexture
  private let reference: ImageTexture?
  private var dragStart: SIMD2<Double>?
  private var dragLast: SIMD2<Double>?
  private var fitted = false
  /// The region the shown histogram counts (`.none`: nothing counted yet).
  private var countedRegion: PixelRegion??
  private var frameNumber = 0
  /// The newest histogram buffer: read on the main actor once its frame completes.
  private var pendingBins: (frame: Int, bins: MTLBuffer)?

  init(
    model: ViewerModel, renderer: ViewerRenderer, texture: ImageTexture, reference: ImageTexture?
  ) {
    self.model = model
    self.renderer = renderer
    self.texture = texture
    self.reference = reference
    super.init(frame: .zero, device: renderer.device)
    delegate = self
    colorPixelFormat = .bgra8Unorm
    framebufferOnly = false
    isPaused = true
    enableSetNeedsDisplay = true
    model.redraw = { [weak self] in self?.needsDisplay = true }
  }

  @available(*, unavailable)
  required init(coder: NSCoder) {
    preconditionFailure("ViewerMTKView is created in code")
  }

  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }

  /// Takes the keyboard (⌥, ⌘0, ⌘1 work before any click) and drops the compare key when the
  /// window stops being key — the ⌥ release then goes to another app.
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    let center = NotificationCenter.default
    center.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
    guard let window else { return }
    window.makeFirstResponder(self)
    center.addObserver(
      self, selector: #selector(windowResignedKey), name: NSWindow.didResignKeyNotification,
      object: window)
  }

  @objc private func windowResignedKey(_ note: Notification) {
    model.compareKeyHeld = false
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(
      NSTrackingArea(
        rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self))
  }

  // MARK: - Drawing

  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    model.viewSize = SIMD2(Double(size.width), Double(size.height))
    if !fitted, size.width > 0, size.height > 0 {
      fitted = true
      model.zoomToFit()
    }
  }

  func draw(in view: MTKView) {
    guard let drawable = currentDrawable, let commands = renderer.queue.makeCommandBuffer() else {
      return
    }
    let frame = model.frame
    // The histogram depends on the image and the region only: count again when they change.
    let counting = countedRegion != .some(frame.region)
    let interval = Self.signposter.beginInterval("frame", id: Self.signposter.makeSignpostID())
    do {
      let bins = try renderer.encode(
        into: commands, image: texture, reference: reference, frame: frame,
        output: drawable.texture, histogram: counting)
      frameNumber += 1
      let number = frameNumber
      if let bins {
        countedRegion = .some(frame.region)
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

  override func scrollWheel(with event: NSEvent) {
    let step = event.hasPreciseScrollingDeltas ? 0.01 : 0.1
    model.zoom(by: exp(Double(event.scrollingDeltaY) * step), atView: viewPoint(event))
  }

  override func magnify(with event: NSEvent) {
    model.zoom(by: 1 + Double(event.magnification), atView: viewPoint(event))
  }

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    let point = viewPoint(event)
    if event.clickCount == 2, model.tool == .region {
      model.clearRegion()
    }
    dragStart = point
    dragLast = point
  }

  override func mouseDragged(with event: NSEvent) {
    guard let start = dragStart, let last = dragLast else { return }
    let point = viewPoint(event)
    model.drag(from: model.tool == .pan ? last : start, to: point, tool: model.tool)
    dragLast = point
    model.hover(atView: point)
  }

  override func mouseUp(with event: NSEvent) {
    dragStart = nil
    dragLast = nil
  }

  override func mouseMoved(with event: NSEvent) {
    model.hover(atView: viewPoint(event))
  }

  override func flagsChanged(with event: NSEvent) {
    model.compareKeyHeld = event.modifierFlags.contains(.option)
  }

  @objc func zoomToFit(_ sender: Any?) { model.zoomToFit() }
  @objc func zoomToActualSize(_ sender: Any?) { model.zoomToActualSize() }

  /// The event's location in drawable pixels, top-left origin.
  private func viewPoint(_ event: NSEvent) -> SIMD2<Double> {
    let point = convert(event.locationInWindow, from: nil)
    let backing = Double(window?.backingScaleFactor ?? 1)
    return SIMD2(Double(point.x), Double(point.y)) * backing
  }
}
