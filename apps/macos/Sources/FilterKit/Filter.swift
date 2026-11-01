internal import Foundation

/// The ONE canonical list of photometric filters (CLAUDE.md): wheel/display order, aliases,
/// narrowband flags.
///
/// Port of `internal/filters/filters.go`; never re-declare a filter list — FilterKit is the leaf
/// module StackKit, ProcessKit and the app all read it from. Frames keep their filter
/// as a `String`, because a custom filter the user has not mapped yet passes through verbatim; this
/// type is the vocabulary that string is checked against.
package enum Filter: String, CaseIterable, Sendable {
  case luminance = "L"
  case red = "R"
  case green = "G"
  case blue = "B"
  case hydrogenAlpha = "Ha"
  case oxygenIII = "OIII"
  case sulfurII = "SII"
  case hydrogenBeta = "Hb"
  case nitrogenII = "NII"

  /// The channel name of a one-shot-colour frame.
  ///
  /// Deliberately not a case: it has no wheel rank, no narrowband answer and no slot in the
  /// emission-screen tables.
  package static let color = "RGB"

  /// Spellings capture programs use for "no filter — this is colour".
  private static let colorAliases: Set<String> = ["rgb", "osc", "color", "colour", "bayer"]

  /// Every alias, lowercased, of each filter.
  ///
  /// Johnson V reads as green (old R/V/B sessions).
  package static let aliases: [String: Self] = [
    "l": .luminance, "lum": .luminance, "luminance": .luminance, "clear": .luminance,
    "r": .red, "red": .red,
    "g": .green, "green": .green, "v": .green,
    "b": .blue, "blue": .blue,
    "ha": .hydrogenAlpha, "h-alpha": .hydrogenAlpha, "halpha": .hydrogenAlpha,
    "h_alpha": .hydrogenAlpha, "hydrogen-alpha": .hydrogenAlpha,
    "oiii": .oxygenIII, "o3": .oxygenIII, "o-iii": .oxygenIII, "oxygen": .oxygenIII,
    "sii": .sulfurII, "s2": .sulfurII, "s-ii": .sulfurII, "sulfur": .sulfurII,
    "sulphur": .sulfurII,
    "hb": .hydrogenBeta, "h-beta": .hydrogenBeta, "hbeta": .hydrogenBeta, "h_beta": .hydrogenBeta,
    "hydrogen-beta": .hydrogenBeta,
    // No "n2" (unlike s2 / o3): `n1/n2` night folders would read as the filter (card 0141).
    "nii": .nitrogenII, "n-ii": .nitrogenII, "nitrogen": .nitrogenII,
  ]

  /// Whether the filter is an emission line rather than broadband (`line` says which).
  package var isNarrowband: Bool { line != nil }

  /// The same aliases under their canonical spelling (`canonical(_:)`), for the second pass.
  private static let canonicalAliases: [String: Self] = Dictionary(
    aliases.map { (canonical($0.key), $0.value) }, uniquingKeysWith: { first, _ in first })

  /// The filter `raw` names, if it is one (card 0163).
  ///
  /// Case and surrounding spaces are ignored; a name with no exact alias is canonicalised
  /// (`canonical(_:)`) and looked up again. No edit distance, no guess: no table hit = `nil`.
  package static func token(_ raw: String) -> Self? {
    let exact = raw.trimmingCharacters(in: .whitespaces).lowercased()
    return aliases[exact] ?? canonicalAliases[canonical(exact)]
  }

  /// `raw` lowercased without what capture programs add around a filter's name: a bandwidth
  /// (`7nm`, `6.5 nm`), separators (`-_ /.`), brackets (`[OIII]`), Greek letters spelled out
  /// (`Hα` → `halpha`).
  static func canonical(_ raw: String) -> String {
    var name = raw.lowercased().replacing(/\d+([.,]\d+)?\s*nm/, with: "")
    name = name.replacingOccurrences(of: "α", with: "alpha")
      .replacingOccurrences(of: "β", with: "beta")
    name.removeAll { "-_/.[]".contains($0) || $0.isWhitespace }
    return name
  }

  /// `raw` abbreviated to its canonical token, or trimmed and kept verbatim when unknown.
  package static func normalize(_ raw: String) -> String {
    token(raw)?.rawValue ?? raw.trimmingCharacters(in: .whitespaces)
  }

  /// Whether the filter name `name` is an emission line.
  package static func isNarrowband(_ name: String) -> Bool {
    Self(rawValue: name)?.isNarrowband ?? false
  }

  /// Position in the canonical order; `allCases.count` for anything custom.
  package static func rank(_ name: String) -> Int {
    allCases.firstIndex { $0.rawValue == name } ?? allCases.count
  }

  /// Canonical order first, then alphabetical for custom names.
  package static func less(_ lhs: String, _ rhs: String) -> Bool {
    let (left, right) = (rank(lhs), rank(rhs))
    return left != right ? left < right : lhs < rhs
  }

  /// The one layer a mono image is made of (`palette.go` resolveMono): L, else Hα, else the first
  /// of `ids` in the canonical order; nil when there is none.
  package static func monoSource(in ids: some Collection<String>) -> String? {
    for preferred in [Self.luminance, .hydrogenAlpha] where ids.contains(preferred.rawValue) {
      return preferred.rawValue
    }
    return ids.min(by: less)
  }

  /// Whether `raw` explicitly says one-shot colour.
  ///
  /// An empty name is unknown, not colour.
  package static func isColor(_ raw: String) -> Bool {
    colorAliases.contains(raw.trimmingCharacters(in: .whitespaces).lowercased())
  }

  /// Whether `raw` names a single band, i.e. filter-wheel evidence (custom names included).
  package static func isMono(_ raw: String) -> Bool {
    let name = raw.trimmingCharacters(in: .whitespaces)
    return !name.isEmpty && !isColor(name)
  }
}
