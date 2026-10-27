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

  private static let hydrogenAlphaLine = Line(
    wavelengthNm: 656.3, displayName: "Hα", continuumFilters: [.red, .luminance], colourPlane: 0)
  private static let oxygenIIILine = Line(
    wavelengthNm: 500.7, displayName: "[OIII]", continuumFilters: [.green, .blue, .luminance],
    colourPlane: 1)
  private static let sulfurIILine = Line(
    wavelengthNm: 671.6, displayName: "[SII]", continuumFilters: [.red, .luminance], colourPlane: 0)

  /// The line this filter isolates, `nil` for a broadband filter (a constant: the predicate
  /// runs per frame in the channel detector).
  package var line: Line? {
    switch self {
    case .hydrogenAlpha: Self.hydrogenAlphaLine
    case .oxygenIII: Self.oxygenIIILine
    case .sulfurII: Self.sulfurIILine
    case .luminance, .red, .green, .blue: nil
    }
  }

  /// The emission lines, in display order.
  package static let narrowband = allCases.filter { $0.line != nil }

  /// The broadband filters, in display order.
  package static let broadband = allCases.filter { $0.line == nil }

  /// Whether the channel `name` is an emission line.
  ///
  /// Not one-shot colour and not a broadband filter, so a custom name (`NII-custom`) is one.
  /// StackKit's bundle roles and ProcessKit's line layers share this rule (card 0136).
  package static func isLineName(_ name: String) -> Bool {
    guard !isColor(name) else { return false }
    return token(name).map { $0.line != nil } ?? true
  }
}
