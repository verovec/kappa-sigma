package import ImageKit

/// A process that moves pixels instead of changing their values (card 0090): its output may have
/// another size, an applied step moves every layer the next steps read with the image (screens
/// read Hα, the star recomposition reads `starless`), and the header's plate solution follows.
///
/// The runner sizes the output by `outputSize`; a mask is refused (a mask blends an output with
/// its input, pixel for pixel, which a moved grid does not have).
package protocol GeometricProcess: ImageProcess {
  /// The output's size for an input of `width` × `height` at `scale`, rows stored bottom-up or
  /// not; values leaving no pixel are refused with the reason.
  func outputSize(width: Int, height: Int, scale: Double, bottomUp: Bool) throws
    -> (width: Int, height: Int)

  /// The header of the full-resolution output of a `width` × `height` image described by
  /// `header`.
  func header(_ header: FITSHeader, width: Int, height: Int, bottomUp: Bool) throws -> FITSHeader
}
