package import FilterKit

/// The panel defaults of each emission line (card 0133).
///
/// What the screens and the injection schemas start from: one table keyed by the filter, so a new
/// line in FilterKit needs one entry here (`LinePanelDefaultsTests` fails otherwise; without it the
/// filter is no `EmissionLine`) and no `switch`.
package struct LinePanelDefaults: Equatable, Sendable {
  /// Screen on by default.
  package let enabled: Bool
  /// Screen opacity.
  package let opacity: Double
  /// Screen tint.
  package let tint: ScreenTint
  /// Injection shares into red, green, blue.
  package let shares: [Double]

  /// The defaults of each line.
  ///
  /// The HOO-over-broadband lines are on by default (screens 0.85 and 0.78); [SII], Hβ and [NII]
  /// wait for the user (card 0141). Hα, [SII] and [NII] inject into red, [OIII] into green and
  /// blue half each, Hβ into blue — at gain 0, so untouched defaults change no pixel.
  package static let table: [Filter: Self] = [
    .hydrogenAlpha: Self(enabled: true, opacity: 0.85, tint: .red, shares: [1, 0, 0]),
    .oxygenIII: Self(
      enabled: true, opacity: 0.78, tint: .teal, shares: [0, 0.5, 0.5]),
    .sulfurII: Self(enabled: false, opacity: 0.6, tint: .gold, shares: [1, 0, 0]),
    .hydrogenBeta: Self(enabled: false, opacity: 0.6, tint: .blue, shares: [0, 0, 1]),
    .nitrogenII: Self(enabled: false, opacity: 0.6, tint: .crimson, shares: [1, 0, 0]),
  ]
}
