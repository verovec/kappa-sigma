/// Decides a frame's type (`classify.go`): IMAGETYP first; for frames neither header nor names
/// typed, the pixel curves of the whole session compared against each other.
package enum FrameClassifier {
  // Thresholds of the statistical fallback, valid for 16-bit and [0,1] float frames.
  static let biasMaxExposureMs = 1500
  static let flatMaxExposureMs = 15000
  static let lightMinPeaks = 8
  static let lightMinBright = 0.01
  static let flatBrightFloorRatio = 4.0
  static let flatMaxNonUniformity = 0.08
  static let biasFloorRatio = 1.5
  /// The exposed-level cut sits a quarter of the way from the darkest frame to the brightest.
  static let exposedMinFraction = 0.25
  /// …and only when the brightest is at least 20× the darkest.
  static let exposedMinRatio = 20.0

  /// The type an IMAGETYP value names (`Light Frame`, `FlatDark`, `OFFSET`…).
  package static func imageType(_ value: String) -> FrameType {
    let text = value.lowercased()
    let flat = text.contains("flat")
    let dark = text.contains("dark")
    if flat && dark { return .darkFlat }
    if flat { return .flat }
    if ["bias", "offset", "zero"].contains(where: text.contains) { return .bias }
    if dark { return .dark }
    if ["light", "object", "science"].contains(where: text.contains) { return .light }
    return .unknown
  }

  /// One type per curve, judged across the batch: stars ⇒ light; short, bright, uniform ⇒ flat;
  /// short and at the floor ⇒ bias; a shutter that saw a scene ⇒ light; starless at an exposure
  /// real lights share ⇒ dark; otherwise light (faint signal is never discarded).
  package static func byStats(_ stats: [FrameStat]) -> [FrameType] {
    let floor = darkFloor(stats)
    let starry = Set(stats.filter(hasStars).map(\.exposureMs))
    let exposed = exposedLevel(stats)
    return stats.map { stat in
      guard stat.measured else { return .light }
      if hasStars(stat) { return .light }
      if isFlat(stat, floor: floor) { return .flat }
      if isBias(stat, floor: floor) { return .bias }
      if let exposed, stat.median >= exposed { return .light }
      return starry.contains(stat.exposureMs) ? .dark : .light
    }
  }

  /// Point sources (gated on a measurable noise floor) or bright structure (a proportion, so
  /// never gated): a capped lens at the true black floor counts noise ripples as peaks.
  package static func hasStars(_ stat: FrameStat) -> Bool {
    stat.brightFraction >= lightMinBright || (stat.mad > 0 && stat.peaks >= lightMinPeaks)
  }

  /// The median above which a frame recorded a scene, when the batch holds clearly black and
  /// clearly exposed frames; `nil` otherwise.
  ///
  /// Can only add lights, never remove them.
  package static func exposedLevel(_ stats: [FrameStat]) -> Double? {
    let medians = stats.filter(\.measured).map(\.median)
    guard let low = medians.min(), let high = medians.max(), high > 0,
      high >= exposedMinRatio * low
    else { return nil }
    return low + exposedMinFraction * (high - low)
  }

  /// The session's dark/bias level: the smallest measured median, 1 when none is positive.
  static func darkFloor(_ stats: [FrameStat]) -> Double {
    guard let floor = stats.filter(\.measured).map(\.median).min(), floor > 0 else { return 1 }
    return floor
  }

  private static func isFlat(_ stat: FrameStat, floor: Double) -> Bool {
    guard stat.exposureMs <= flatMaxExposureMs else { return false }
    let uniform = stat.median > 0 && stat.mad / stat.median <= flatMaxNonUniformity
    return stat.median >= floor * flatBrightFloorRatio && uniform
  }

  private static func isBias(_ stat: FrameStat, floor: Double) -> Bool {
    stat.exposureMs <= biasMaxExposureMs && stat.median <= floor * biasFloorRatio
  }
}
