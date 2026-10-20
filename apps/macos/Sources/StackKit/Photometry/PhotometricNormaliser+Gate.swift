internal import Foundation

extension PhotometricNormaliser {
  /// The no-clip gate (`degradeClippingTransform`): a transform pushing a healthy sky below zero at
  /// 3σ is degraded to the background ratio, else to a background offset; nil when it is clean or
  /// the group's own sky already straddles zero.
  package static func degradeClipping(
    _ label: String, _ transform: PhotomTransform, group: FrameCurve, reference: FrameCurve
  ) -> (PhotomTransform, String)? {
    guard clipsSky(transform, group), group.background - 3 * group.noise >= 0 else { return nil }
    let degraded: PhotomTransform
    if let ratio = CurveFit.backgroundRatio(group, reference) {
      degraded = PhotomTransform(
        scale: ratio, offset: reference.background.addingProduct(-ratio, group.background),
        method: .bgMatched)
    } else {
      degraded = PhotomTransform(scale: 1, offset: reference.background - group.background, method: .offsetOnly)
    }
    let note =
      "group \"\(label)\": transform ×\(String(format: "%.3g", transform.scale)) "
      + "\(String(format: "%+.4g", transform.offset)) would clip its sky below zero — "
      + "degraded to \(degraded.method.rawValue) (×\(String(format: "%.3g", degraded.scale)) "
      + "\(String(format: "%+.4g", degraded.offset)))"
    return (degraded, note)
  }

  /// `scale · bg + offset − 3 · scale · noise < 0`.
  package static func clipsSky(_ transform: PhotomTransform, _ curve: FrameCurve) -> Bool {
    transform.scale * curve.background + transform.offset - 3 * transform.scale * curve.noise < 0
  }

  /// The notes a transform's flags call for (`transformWarnings`).
  static func warnings(_ label: String, _ transform: PhotomTransform) -> [String] {
    var notes: [String] = []
    let scale = String(format: "%.3g", transform.scale)
    if transform.clamped {
      notes.append("group \"\(label)\": photometric scale clamped to [0.1, 10] (measured out of range)")
    }
    if transform.metaDisagree {
      notes.append("group \"\(label)\": measured scale \(scale) disagrees with header exposure/gain — check GAIN header")
    }
    if transform.metaSeeded {
      notes.append(
        "group \"\(label)\": percentile curve too flat to measure (narrowband/sky pedestal) — scale \(scale) "
          + "seeded from header exposure/gain")
    }
    if transform.method == .bgMatched {
      notes.append(
        "group \"\(label)\": scale \(scale) matched from the measured sky backgrounds (no trustworthy header prediction)")
    }
    if transform.backgroundDisagree {
      notes.append(
        "group \"\(label)\": the measured sky-background ratio grossly disagrees with the confirmed header seed ×\(scale) — "
          + "residual pedestal (missing darks) or a strong sky-brightness difference; the seed (object flux) was kept")
    }
    return notes
  }
}
