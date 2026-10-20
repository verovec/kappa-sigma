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

  /// The image shown (linear data, never modified by the viewer).
  package let image: AstroImage
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
  /// Called when `frame` changes (the Metal view redraws on demand).
  @ObservationIgnored package var redraw: (@MainActor () -> Void)?

  private var split: Double?
  private var autoSTF: [STFParameters]

  /// A viewer of `image`, autostretched (`autoSTF` when the caller computed it off the main
  /// actor), at 1:1 until the view has a size (then `zoomToFit`).
  package init(image: AstroImage, autoSTF precomputed: [STFParameters]? = nil) {
    self.image = image
    let auto = precomputed ?? AutoSTF.compute(planes: image.planes, linked: false)
    autoSTF = auto
    manualSTF = auto
    frame = ViewerFrame(transform: ViewTransform(scale: 1, origin: .zero), stf: auto)
    frame.flipRows = image.metadata.rowOrder == .bottomUp
  }

  /// The autostretch currently offered.
  package var autoParameters: [STFParameters] { autoSTF }

  /// The whole image in the view (⌘0).
  package func zoomToFit() {
    frame.transform = .fit(
      imageWidth: image.width, imageHeight: image.height, viewWidth: viewSize.x,
      viewHeight: viewSize.y)
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
      autoSTF = AutoSTF.compute(planes: image.planes, linked: linked)
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
