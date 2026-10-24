package import ImageKit
internal import Observation

/// The viewer's state, as values the UI shows and edits.
///
/// `frame` is exactly what the GPU draws. View coordinates are drawable pixels, top-left origin.
@MainActor
@Observable
package final class ViewerModel {
  /// Where the display stretch comes from.
  package enum Stretch: String, CaseIterable, Sendable {
    /// Siril's autostretch (shadows −2.8 MADN, background 0.25).
    case auto
    /// The user's numbers, starting from the autostretch.
    case manual
    /// No stretch: clamp(x).
    case off
  }

  /// What a drag does.
  package enum Tool: String, CaseIterable, Sendable {
    /// Moves the image.
    case pan
    /// Draws the region.
    case region
    /// Places the compare split.
    case split
  }

  /// The image shown (linear data, never modified by the viewer; `replace` swaps it).
  package private(set) var image: AstroImage
  /// What the GPU draws next.
  package var frame: ViewerFrame {
    didSet { redraw?() }
  }
  /// Auto, manual or off.
  package var stretch = Stretch.auto {
    didSet {
      // Manual starts from the stretch on screen; from Off it keeps the last manual numbers.
      if stretch == .manual, oldValue == .auto {
        manualSTF = autoSTF
      } else {
        applyStretch()
      }
    }
  }
  /// One autostretch for every channel (the mean of their statistics) instead of one each.
  package var linked = false {
    didSet { applyStretch() }
  }
  /// The manual stretch per channel.
  package var manualSTF: [STFParameters] {
    didSet { applyStretch() }
  }
  /// The drag tool.
  package var tool = Tool.pan
  /// The compare key is down: the reference fills the view.
  package var compareKeyHeld = false {
    didSet { applyCompare() }
  }
  /// The view's size in drawable pixels.
  package var viewSize = SIMD2<Double>(1, 1)
  /// Image pixel under the cursor.
  package private(set) var readout: PixelReadout?
  /// The last frame's histogram, `[channel][bin]`.
  package var histogram: [[Int]] = []
  /// The « View » panel is beside the image (card 0126); display only, the frame never changes.
  package var showsPanel: Bool {
    didSet {
      panelSetting.showsPanel = showsPanel
      panelToggled?()
    }
  }
  /// Where `showsPanel` is remembered.
  @ObservationIgnored private let panelSetting: ViewerPanelSetting
  /// Called when `showsPanel` changes (the surface takes the keyboard back from a hidden panel).
  @ObservationIgnored package var panelToggled: (@MainActor () -> Void)?
  /// Called when `frame` changes (the Metal view redraws on demand).
  @ObservationIgnored package var redraw: (@MainActor () -> Void)?

  /// Each channel's median and MADN, measured once: the autostretch and the σ controls read them.
  package private(set) var statistics: [STFMapping]
  private var linkedStatistics: [STFMapping]
  private var split: Double?
  private var autoSTF: [STFParameters]
  /// The stretch a histogram drag started from: every event of the drag maps from it, so a
  /// display-domain drag never compounds on its own result.
  private var dragOrigin: [STFParameters]?

  /// A viewer of `image`, autostretched (`statistics` when the caller measured them off the main
  /// actor), at 1:1 until the view has a size (then `zoomToFit`); the panel as `panelSetting`
  /// last left it.
  package init(
    image: AstroImage, statistics measured: [STFMapping]? = nil,
    panelSetting: ViewerPanelSetting = ViewerPanelSetting()
  ) {
    self.image = image
    self.panelSetting = panelSetting
    showsPanel = panelSetting.showsPanel
    let statistics = measured ?? STFMapping.measure(planes: image.planes, linked: false)
    self.statistics = statistics
    linkedStatistics = STFMapping.linked(statistics)
    let auto = Self.autostretch(statistics)
    autoSTF = auto
    manualSTF = auto
    frame = ViewerFrame(transform: ViewTransform(scale: 1, origin: .zero), stf: auto)
    frame.flipRows = image.metadata.rowOrder == .bottomUp
  }

  /// Shows `image` in place of the current one (the Studio's new head, card 0087).
  ///
  /// Zoom, tool, region, compare and the stretch mode stay; the autostretch follows the new
  /// image; manual numbers stay unless the plane count changed. A region does not survive
  /// another size (a crop or a quarter turn, card 0090): its pixels are not the new image's.
  package func replace(image: AstroImage, statistics measured: [STFMapping]? = nil) {
    let statistics = measured ?? STFMapping.measure(planes: image.planes, linked: false)
    let samePlanes = statistics.count == self.statistics.count
    let resized = image.width != self.image.width || image.height != self.image.height
    if resized {
      frame.region = nil
    }
    self.image = image
    // The zoom is in the old image's pixels: a crop or a quarter turn is fitted again (a head of
    // the same size keeps where the user looks).
    if resized { zoomToFit() }
    self.statistics = statistics
    linkedStatistics = STFMapping.linked(statistics)
    autoSTF = Self.autostretch(statistics)
    if !samePlanes { manualSTF = autoSTF }
    frame.flipRows = image.metadata.rowOrder == .bottomUp
    applyStretch()
  }

  /// The autostretch currently offered.
  package var autoParameters: [STFParameters] { autoSTF }

  /// The statistics behind the stretch of `channel`: its own, or the mean over the channels when
  /// linked.
  package func mapping(for channel: Int) -> STFMapping {
    (linked ? linkedStatistics : statistics)[channel]
  }

  /// Back to the autostretch (the « Reset to auto » button).
  package func resetToAuto() {
    stretch = .auto
  }

  /// A histogram handle of `channel` dropped at `position` (0…1 of the axis, in the frame's
  /// histogram domain).
  ///
  /// From Auto, Manual starts from the auto values; only that parameter moves. Off has no
  /// handles: nothing changes.
  package func dragHandle(_ handle: STFHandle, channel: Int, to position: Double) {
    guard stretch != .off, manualSTF.indices.contains(channel) else { return }
    if stretch == .auto { stretch = .manual }
    let origin = dragOrigin ?? manualSTF
    dragOrigin = origin
    manualSTF[channel] = origin[channel].dragging(handle, to: position, in: frame.histogramDomain)
  }

  /// The drag ended: the next one starts from the stretch it finds.
  package func endHandleDrag() {
    dragOrigin = nil
  }

  private static func autostretch(_ statistics: [STFMapping]) -> [STFParameters] {
    statistics.map {
      $0.parameters(sigma: AutoSTF.shadowsClip, targetBackground: AutoSTF.targetBackground)
    }
  }

  /// The whole image in the view (⌘0).
  package func zoomToFit() {
    frame.transform = .fit(
      imageWidth: image.width, imageHeight: image.height, viewWidth: viewSize.x,
      viewHeight: viewSize.y)
  }

  /// The view is now `size`: a window resize, the panel hidden or shown.
  ///
  /// The image point under the view centre stays there at the same zoom; an image that was whole
  /// and no longer is is fitted again. An empty size (a collapsing layout) is ignored: the next
  /// real one is compared with the last real one.
  package func resizeView(to size: SIMD2<Double>) {
    guard size.x > 0, size.y > 0 else { return }
    let old = viewSize
    viewSize = size
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

  /// 1:1 around the view centre (⌘1).
  package func zoomToActualSize() {
    frame.transform = frame.transform.oneToOne(viewWidth: viewSize.x, viewHeight: viewSize.y)
  }

  /// Zooms by `factor` (> 1 magnifies) around a view point.
  package func zoom(by factor: Double, atView point: SIMD2<Double>) {
    frame.transform = frame.transform.zoomed(by: factor, aroundViewX: point.x, viewY: point.y)
  }

  /// One drag step with `tool`: pan by the step, a region from `start` to `end`, the split at
  /// `end`.
  package func drag(from start: SIMD2<Double>, to end: SIMD2<Double>, tool: Tool) {
    switch tool {
    case .pan:
      frame.transform = frame.transform.panned(byViewX: end.x - start.x, viewY: end.y - start.y)
    case .region:
      frame.region = frame.transform.region(
        fromViewX: start.x, viewY: start.y, toViewX: end.x, viewY: end.y,
        imageWidth: image.width, imageHeight: image.height)
    case .split:
      split = end.x
      applyCompare()
    }
  }

  /// Back to the whole image for the histogram.
  package func clearRegion() {
    frame.region = nil
  }

  /// No split: the current image everywhere.
  package func clearSplit() {
    split = nil
    applyCompare()
  }

  /// Reads the pixel under a view point.
  package func hover(atView point: SIMD2<Double>) {
    let position = frame.transform.imagePoint(viewX: point.x, viewY: point.y)
    guard position.x >= 0, position.y >= 0 else {
      readout = nil
      return
    }
    let row = Int(position.y.rounded(.down))
    readout = PixelReadout(
      image: image, x: Int(position.x.rounded(.down)),
      y: frame.flipRows ? image.height - 1 - row : row)
  }

  private func applyStretch() {
    switch stretch {
    case .auto:
      autoSTF = Self.autostretch(linked ? linkedStatistics : statistics)
      frame.stf = autoSTF
    case .manual:
      frame.stf = manualSTF
    case .off:
      frame.stf = nil
    }
  }

  private func applyCompare() {
    if compareKeyHeld {
      frame.compare = .reference
    } else if let split {
      frame.compare = .split(atViewX: split)
    } else {
      frame.compare = .off
    }
  }
}
