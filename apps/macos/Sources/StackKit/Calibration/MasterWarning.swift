internal import Foundation

/// A master statistic past its documented threshold (card 0071): shown with the value and the
/// threshold, never acted on — the user keeps, excludes or rebuilds (R2).
package struct MasterWarning: Equatable, Sendable {
  /// Which threshold.
  package enum Kind: String, CaseIterable, Sendable {
    /// Flat corners brighter than its centre: a light leak or a dawn gradient (the M 45 lot).
    case cornersBrighter
    /// Flat median below 10 % of full scale (M 45: 3 770 ADU ≈ 6 %; aim 25–40 %).
    case underExposed
    /// More than 0.1 % of the pixels at full scale.
    case clipped
    /// Dark with more than 0.5 % of its pixels above median + 10 σ: a warm or leaky dark.
    case hotPixels
  }

  package var kind: Kind
  package var message: String

  /// The documented thresholds.
  package static let underExposedFraction = 0.10
  package static let clippedPct = 0.1
  package static let hotPixelPct = 0.5

  /// Every threshold `stats` crosses, in `Kind` order.
  package static func all(for stats: MasterStats) -> [Self] {
    guard stats.pixelCount > 0 else { return [] }
    var out: [Self] = []
    if let vignetting = stats.vignettingPct, vignetting > 0 {
      out.append(
        Self(
          kind: .cornersBrighter,
          message: "corners \(percent(vignetting)) brighter than the centre (threshold: a healthy "
            + "flat always has darker corners) — light leak or dawn gradient?"))
    }
    let level = stats.median / stats.fullScale
    if stats.type == .flat && level < underExposedFraction {
      out.append(
        Self(
          kind: .underExposed,
          message: "median at \(percent(level * 100)) of full scale (threshold "
            + "\(percent(underExposedFraction * 100))) — under-exposed flat, aim for 25–40 %"))
    }
    if stats.clippedPct > clippedPct {
      out.append(
        Self(
          kind: .clipped,
          message: "\(percent(stats.clippedPct)) of the pixels at full scale (threshold "
            + "\(percent(clippedPct)))"))
    }
    if let hot = stats.hotPixels, stats.pixelCount > 0 {
      let share = Double(hot) / Double(stats.pixelCount) * 100
      if share > hotPixelPct {
        out.append(
          Self(
            kind: .hotPixels,
            message: "\(hot) hot pixels, \(percent(share)) (threshold \(percent(hotPixelPct)))"
              + " — a warm dark, or light reached the sensor?"))
      }
    }
    return out
  }

  /// Two decimals, as the stats line writes them.
  private static func percent(_ value: Double) -> String {
    String(format: "%.2f %%", value)
  }
}
