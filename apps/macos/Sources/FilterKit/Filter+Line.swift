/// The physics of an emission line (card 0133): its wavelength, how panels write it, and the
/// broadband references its continuum is estimated against — the one table StackKit's fit and
/// ProcessKit's line processes both read.
extension Filter {
  /// An emission line's physics.
  package struct Line: Hashable, Sendable {
    /// Rest wavelength, nm.
    package let wavelengthNm: Double
    /// How panels write it (« Hα », « [OIII] »).
    package let displayName: String
    /// The broadband filters its continuum is fitted against, in order.
    package let continuumFilters: [Filter]
    /// The plane of a one-shot-colour base to fall back on (0 red, 1 green, 2 blue).
    package let colourPlane: Int
  }

  /// The line this filter isolates, `nil` for a broadband filter.
  package var line: Line? {
    switch self {
    case .hydrogenAlpha:
      Line(
        wavelengthNm: 656.3, displayName: "Hα", continuumFilters: [.red, .luminance],
        colourPlane: 0)
    case .oxygenIII:
      Line(
        wavelengthNm: 500.7, displayName: "[OIII]", continuumFilters: [.green, .blue, .luminance],
        colourPlane: 1)
    case .sulfurII:
      Line(
        wavelengthNm: 671.6, displayName: "[SII]", continuumFilters: [.red, .luminance],
        colourPlane: 0)
    case .luminance, .red, .green, .blue: nil
    }
  }

  /// The emission lines, in display order.
  package static let narrowband = allCases.filter { $0.line != nil }

  /// The broadband filters, in display order.
  package static let broadband = allCases.filter { $0.line == nil }
}
