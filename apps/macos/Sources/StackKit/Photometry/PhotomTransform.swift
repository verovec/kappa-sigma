/// The affine map reference ≈ scale · frame + offset (`photom.Transform`), with how its scale was
/// established and the flags a run records.
package struct PhotomTransform: Equatable, Sendable {
  /// Which evidence set the scale (the legacy ladder, most authoritative first).
  package enum Method: String, CaseIterable, Sendable {
    /// Theil–Sen fit over signal-bearing curves.
    case measured
    /// The exposure/gain prediction (flat curves).
    case seeded
    /// The measured sky-background ratio.
    case bgMatched = "bg-matched"
    /// The background offset alone (the no-clip degrade of last resort).
    case offsetOnly = "offset-only"
    /// Nothing usable.
    case identity
  }

  package var scale = 1.0
  package var offset = 0.0
  package var residual = 0.0
  package var method = Method.identity
  /// A measured scale outside [0.1, 10], clamped.
  package var clamped = false
  /// The measured scale is far from the exposure/gain prediction (the measurement is kept).
  package var metaDisagree = false
  /// The curves were too flat to measure: the scale is the prediction.
  package var metaSeeded = false
  /// The background ratio grossly contradicts a kept seed.
  package var backgroundDisagree = false

  /// A transform.
  package init(scale: Double = 1, offset: Double = 0, method: Method = .identity) {
    self.scale = scale
    self.offset = offset
    self.method = method
  }

  /// Close enough to identity to leave a group untouched (`isIdentity`).
  func isIdentity(referenceNoise: Double) -> Bool {
    abs(scale - 1) < 0.02 && abs(offset) < 0.2 * referenceNoise
  }

  /// `scale · p + offset` in double, rounded to float32 (`applyToImage`, fused as on arm64).
  package func apply(_ value: Float) -> Float {
    Float(offset.addingProduct(scale, Double(value)))
  }
}
