/// Swift mirror of `Shaders/Lines.h` — the header is the definition; `LinesHeaderTests` pins the
/// slot count and the layouts.
///
/// The injection and screen kernels loop over the lines bound, in canonical order; a line that
/// would change no pixel is not bound (card 0136).
package enum LineKernels {
  /// `MAX_LINES`: the line slots of each kernel.
  package static let maxLines = 8

  /// `InjectLine`: what one line adds per unit of excess to each base plane, its continuum scale
  /// and black point.
  package struct InjectLine {
    package var weight: (Float, Float, Float)
    package var k: Float
    package var black: Float
  }

  /// `ScreenLine`: one line's opacity · blend and tint.
  package struct ScreenLine {
    package var alpha: Float
    package var tint: (Float, Float, Float)
  }
}
