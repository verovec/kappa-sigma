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
  /// Current, reference, or split.
  package var compare = Compare.off
  /// The histogram's window; `nil` counts the whole image.
  package var region: PixelRegion?
  /// Histogram sampling step: 2 counts a quarter of the pixels.
  package var histogramStride = 2
  /// The stored rows are bottom-up: display row 0 is the last stored row. `transform` and
  /// `region` are in display coordinates.
  package var flipRows = false
  /// Tints the view red where the process mask is (the renderer's `mask` texture).
  package var maskOverlay = false

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

  /// `region` in stored rows, for the histogram.
  package func storedRegion(imageHeight: Int) -> PixelRegion? {
    guard var region, flipRows else { return region }
    region.y = imageHeight - region.y - region.height
    return region
  }
}
