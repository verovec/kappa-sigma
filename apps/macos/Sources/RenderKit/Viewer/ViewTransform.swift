/// Where the image sits in the view.
///
/// `image = origin + view × scale`, in pixels of each (the view in drawable pixels, not points,
/// the image in display rows: top row first). The `display` kernel samples view pixel centres
/// with the same mapping.
package struct ViewTransform: Equatable, Sendable {
  /// Image pixels per view pixel: 1 is 1:1, > 1 zoomed out.
  package var scale: Double
  /// Image position of the view's top-left corner.
  package var origin: SIMD2<Double>

  /// Zoom limits, image pixels per view pixel.
  package static let scales = (1.0 / 64)...64.0

  /// A transform with `scale` and `origin`.
  package init(scale: Double, origin: SIMD2<Double>) {
    self.scale = scale
    self.origin = origin
  }

  /// The whole image in the view, centred (⌘0).
  package static func fit(
    imageWidth: Int, imageHeight: Int, viewWidth: Double, viewHeight: Double
  ) -> Self {
    let image = SIMD2(Double(imageWidth), Double(imageHeight))
    let view = SIMD2(max(viewWidth, 1), max(viewHeight, 1))
    let scale = max(image.x / view.x, image.y / view.y)
    return Self(scale: scale, origin: (image - view * scale) / 2)
  }

  /// The image position under the view point (`viewX`, `viewY`).
  package func imagePoint(viewX: Double, viewY: Double) -> SIMD2<Double> {
    origin + SIMD2(viewX, viewY) * scale
  }

  /// 1:1, keeping the image point under the view centre (⌘1).
  package func oneToOne(viewWidth: Double, viewHeight: Double) -> Self {
    let centre = SIMD2(viewWidth, viewHeight) / 2
    return Self(scale: 1, origin: origin + centre * scale - centre)
  }

  /// Zoomed in by `factor` (> 1 magnifies), keeping the image point under the cursor fixed.
  package func zoomed(by factor: Double, aroundViewX viewX: Double, viewY: Double) -> Self {
    guard factor > 0, factor.isFinite else { return self }
    let next = min(max(scale / factor, Self.scales.lowerBound), Self.scales.upperBound)
    let cursor = SIMD2(viewX, viewY)
    return Self(scale: next, origin: origin + cursor * scale - cursor * next)
  }

  /// Moved with a drag of (`viewX`, `viewY`) view pixels: the image follows the pointer.
  package func panned(byViewX viewX: Double, viewY: Double) -> Self {
    Self(scale: scale, origin: origin - SIMD2(viewX, viewY) * scale)
  }

  /// The image pixels under a drag between two view points, clipped to the image; `nil` when
  /// nothing of the image is inside.
  package func region(
    fromViewX x0: Double, viewY y0: Double, toViewX x1: Double, viewY y1: Double,
    imageWidth: Int, imageHeight: Int
  ) -> PixelRegion? {
    let start = imagePoint(viewX: x0, viewY: y0)
    let end = imagePoint(viewX: x1, viewY: y1)
    let low = SIMD2(
      max(min(start.x, end.x).rounded(.down), 0), max(min(start.y, end.y).rounded(.down), 0))
    let high = SIMD2(
      min(max(start.x, end.x).rounded(.up), Double(imageWidth)),
      min(max(start.y, end.y).rounded(.up), Double(imageHeight)))
    guard high.x > low.x, high.y > low.y else { return nil }
    return PixelRegion(
      x: Int(low.x), y: Int(low.y), width: Int(high.x - low.x), height: Int(high.y - low.y))
  }
}
