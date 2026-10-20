/// A decoded image: planar float32 (`planes[c][y * width + x]`), one plane (mono) or three (RGB),
/// rows in the file's order, values physical (BZERO + BSCALE · stored).
///
/// A non-Sendable class: a 22 Mpx RGB image is ~260 MB, so it moves between isolation domains
/// with `sending`, never by copy (swift-conventions.md).
package final class AstroImage {
  /// Width in pixels.
  package let width: Int
  /// Height in pixels.
  package let height: Int
  /// The planes; each holds `width * height` values.
  package var planes: [[Float]]
  /// What the header said.
  package var metadata: ImageMetadata

  /// An image from its planes.
  package init(width: Int, height: Int, planes: [[Float]], metadata: ImageMetadata) {
    self.width = width
    self.height = height
    self.planes = planes
    self.metadata = metadata
  }
}
