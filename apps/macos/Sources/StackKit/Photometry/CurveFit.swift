/// Fits a frame's curve onto a reference's (`photom.FitCurves`): a Theil–Sen slope over P5…P97.5,
/// the median offset, the median misfit. A flat curve (span ≈ noise) is not measured: its scale is
/// seeded from the exposure/gain prediction, else the background ratio, else identity.
package enum CurveFit {
  /// The fit probes: P5 … P97.5.
  static let fitRange = 0...11
  static let scaleBounds = 0.1...10.0
  static let tiny = 1e-9
  /// The accepted measured/predicted ratio.
  static let metaBounds = 0.67...1.5
  static let backgroundFloorSigmas = 2.0
  static let seedDisagreeK = 3.0
  static let flatSpanSigmas = 5.0

  /// reference ≈ scale · frame + offset, and how it was established.
  package static func fit(
    _ frame: FrameCurve, onto reference: FrameCurve, frameMeta: PhotomMeta = PhotomMeta(),
    referenceMeta: PhotomMeta = PhotomMeta()
  ) -> PhotomTransform {
    let expected = PhotomMeta.expectedScale(frame: frameMeta, reference: referenceMeta)
    var transform = PhotomTransform(method: .measured)
    var raw = 1.0
    if isFlat(frame) || isFlat(reference) {
      (raw, transform.method) = flatScale(frame, reference, expected: expected)
      if let ratio = backgroundRatio(frame, reference), transform.method == .seeded,
        raw > seedDisagreeK * ratio || ratio > seedDisagreeK * raw
      {
        transform.backgroundDisagree = true
      }
    } else {
      raw = theilSen(frame, reference)
    }
    transform.offset = medianOffset(frame, reference, scale: raw)
    transform.residual = residual(frame, reference, scale: raw, offset: transform.offset)
    transform.metaDisagree = expected > 0 && !metaBounds.contains(raw / expected)
    transform.scale = raw
    if transform.method == .measured, !scaleBounds.contains(raw) {
      transform.scale = min(max(raw, scaleBounds.lowerBound), scaleBounds.upperBound)
      transform.clamped = true
    }
    transform.metaSeeded = transform.method == .seeded
    return transform
  }

  /// A prediction always leads on flat curves; then the background ratio; then identity.
  static func flatScale(_ frame: FrameCurve, _ reference: FrameCurve, expected: Double)
    -> (Double, PhotomTransform.Method)
  {
    if expected > 0 { return (expected, .seeded) }
    if let ratio = backgroundRatio(frame, reference) { return (ratio, .bgMatched) }
    return (1, .identity)
  }

  /// reference.bg / frame.bg, when both backgrounds sit clear of zero and of their own noise.
  static func backgroundRatio(_ frame: FrameCurve, _ reference: FrameCurve) -> Double? {
    for curve in [frame, reference]
    where curve.background <= tiny || curve.background < backgroundFloorSigmas * curve.noise {
      return nil
    }
    return reference.background / frame.background
  }

  /// The fit span is within `flatSpanSigmas` noise sigmas: nothing but sky in the probes.
  static func isFlat(_ curve: FrameCurve) -> Bool {
    curve.q[fitRange.upperBound] - curve.q[fitRange.lowerBound] < flatSpanSigmas * curve.noise
  }

  /// The median of pairwise slopes; 1 when every frame gap is flat.
  static func theilSen(_ frame: FrameCurve, _ reference: FrameCurve) -> Double {
    var slopes: [Double] = []
    for first in fitRange {
      for second in (first + 1)..<(fitRange.upperBound + 1) {
        let gap = frame.q[second] - frame.q[first]
        guard abs(gap) > tiny else { continue }
        slopes.append((reference.q[second] - reference.q[first]) / gap)
      }
    }
    return slopes.isEmpty ? 1 : PhotomStats.median(slopes)
  }

  static func medianOffset(_ frame: FrameCurve, _ reference: FrameCurve, scale: Double) -> Double {
    // Fused as Go fuses `a - s*b` on arm64.
    PhotomStats.median(fitRange.map { reference.q[$0].addingProduct(-scale, frame.q[$0]) })
  }

  /// The median |misfit| over the probes, over the reference's signal span (P97.5 − background).
  static func residual(
    _ frame: FrameCurve, _ reference: FrameCurve, scale: Double, offset: Double
  ) -> Double {
    let span = max(tiny, reference.q[fitRange.upperBound] - reference.background)
    return PhotomStats.median(
      fitRange.map { abs(reference.q[$0] - offset.addingProduct(scale, frame.q[$0])) / span })
  }
}
