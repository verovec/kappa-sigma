/// User-visible notes about a master's own pool (`lonePromotionNote`, `thinDarkPoolNote`).
package enum MasterNotes {
  /// A single-frame pool cannot be stacked (Siril has no one-image sequences): the lone frame is
  /// promoted, without rejection — nor, for a flat, flat-bias calibration.
  package static func lonePromotion(_ name: String, type: MasterType) -> String {
    let suffix = type == .flat ? ", no flat-bias calibration" : ""
    return "master \(name): single-frame pool — the lone frame was promoted unstacked "
      + "(no outlier rejection\(suffix))"
  }

  /// Two darks degenerate every rejection to a mean: a cosmic ray survives into every light.
  /// Bias and flats are high-signal frames, merely noisy at two; one frame is `lonePromotion`.
  package static func thinDarkPool(_ name: String, type: MasterType, frames: Int) -> String? {
    guard frames == 2, type.isThermal else { return nil }
    return "master \(name): 2-frame pool — outlier rejection needs at least 3 darks, so a "
      + "cosmic-ray hit in either frame survives into the master"
  }
}
