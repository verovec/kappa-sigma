/// A screen transfer function for one channel: shadows clip, midtone, highlights clip.
///
/// Display only: it changes what is shown, never the data (R2: the viewer's stretch is not a
/// process). Values applied = values shown, so the viewer prints these numbers.
package struct STFParameters: Equatable, Sendable {
  /// Black point c0.
  package var shadows: Double
  /// Midtone balance m.
  package var midtone: Double
  /// White point c1.
  package var highlights: Double

  /// A stretch.
  package init(shadows: Double, midtone: Double, highlights: Double) {
    self.shadows = shadows
    self.midtone = midtone
    self.highlights = highlights
  }

  /// No stretch: the display is clamp(x).
  package static let identity = Self(shadows: 0, midtone: 0.5, highlights: 1)

  /// The displayed value of a linear value x.
  package func display(_ x: Double) -> Double {
    let range = highlights - shadows
    guard range > 0 else { return x >= highlights ? 1 : 0 }
    let rescaled = min(max((x - shadows) / range, 0), 1)
    return MTF.apply(midtone, rescaled)
  }
}
