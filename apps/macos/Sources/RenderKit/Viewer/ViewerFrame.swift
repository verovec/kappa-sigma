/// Everything a viewer frame shows, as values: the user's settings, applied exactly (R2).
package struct ViewerFrame: Equatable, Sendable {
  /// What the compare key and split show.
  package enum Compare: Equatable, Sendable {
    /// The current image.
    case off
    /// The reference everywhere (compare key held).
    case reference
    /// The reference left of a view column, the current image right of it.
    case split(atViewX: Double)
  }

  /// Zoom and pan.
  package var transform: ViewTransform
  /// The display stretch per channel; `nil` shows clamp(x).
  package var stf: [STFParameters]?
  /// Tints pixels ≥ 1 red and ≤ 0 blue.
  package var clippingOverlay = false
  /// The clipping overlay judges the average under each view pixel (zoomed out, card 0110).
  ///
  /// Decided on the scale the kernel receives (a `Float`), so the panel never disagrees with the
  /// GPU just above 1:1.
  package var clipsOnTheAverage: Bool { clippingOverlay && Float(transform.scale) > 1 }
  /// Current, reference, or split.
  package var compare = Compare.off
  /// The histogram's window; `nil` counts the whole image.
  package var region: PixelRegion?
  /// Histogram sampling step: 2 counts a quarter of the pixels.
  package var histogramStride = 2
  /// Which values the histogram counts: the linear data, or what the stretch displays.
  package var histogramDomain = HistogramDomain.linear
  /// The stored rows are bottom-up: display row 0 is the last stored row. `transform` and
  /// `region` are in display coordinates.
  package var flipRows = false
  /// Tints the view red where the process mask is (the renderer's `mask` texture).
  package var maskOverlay = false
  /// Grey level around the image; `ViewerMTKView` sets the canvas token of its appearance, other
  /// renders keep black.
  package var canvasGrey: Float = 0

  /// A frame at `transform` with `stf`.
  package init(transform: ViewTransform, stf: [STFParameters]?) {
    self.transform = transform
    self.stf = stf
  }

  /// The display kernel's uniforms for `image`.
  package func uniforms(for image: ImageTexture) -> DisplayUniforms {
    var uniforms = DisplayUniforms(image: image, stf: stf)
    uniforms.scale = Float(transform.scale)
    uniforms.originX = Float(transform.origin.x)
    uniforms.originY = Float(transform.origin.y)
    uniforms.clippingOverlay = clippingOverlay ? 1 : 0
    uniforms.flipRows = flipRows ? 1 : 0
    uniforms.maskOverlay = maskOverlay ? 1 : 0
    uniforms.canvasGrey = canvasGrey
    switch compare {
    case .off:
      uniforms.compareMode = 0
    case .reference:
      uniforms.compareMode = 1
    case .split(let column):
      uniforms.compareMode = 2
      uniforms.splitX = Float(column)
    }
    return uniforms
  }

  /// What the histogram depends on: the viewer counts again only when this changes.
  package struct HistogramInput: Equatable, Sendable {
    /// The window counted (display rows).
    package let region: PixelRegion?
    /// The sampling step.
    package let stride: Int
    /// The stretch binned through, in the display domain only.
    package let stf: [STFParameters]?
  }

  /// The stretch the histogram bins through: the frame's in the display domain, none otherwise.
  package var histogramSTF: [STFParameters]? { histogramDomain == .display ? stf : nil }

  /// The histogram's inputs.
  package var histogramInput: HistogramInput {
    HistogramInput(region: region, stride: histogramStride, stf: histogramSTF)
  }

  /// `region` in stored rows, for the histogram.
  package func storedRegion(imageHeight: Int) -> PixelRegion? {
    guard var region, flipRows else { return region }
    region.y = imageHeight - region.y - region.height
    return region
  }
}
