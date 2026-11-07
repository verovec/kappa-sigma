package import Foundation

/// Numbers written in a locale, the one core the viewer and the app's `AstroFormat` share
/// (card 0074): Foundation `FormatStyle`, a U+2212 minus, and a dot as the decimal mark in every
/// language (PO 07/11 « point partout », card 0178); the locale keeps its grouping.
package enum LocaleNumber {
  /// An integer with the locale's grouping (`20 880`, `20,880`), never a dot between groups.
  package static func integer(_ value: Int, locale: Locale) -> String {
    dotted(minus(value.formatted(.number.locale(locale))), locale: locale)
  }

  /// A decimal with `minFractionDigits`…`maxFractionDigits` digits after the dot.
  package static func decimal(
    _ value: Double, locale: Locale, maxFractionDigits: Int, minFractionDigits: Int = 0,
    grouping: Bool = false
  ) -> String {
    let style = FloatingPointFormatStyle<Double>.number.locale(locale)
      .precision(.fractionLength(minFractionDigits...max(minFractionDigits, maxFractionDigits)))
      .grouping(grouping ? .automatic : .never)
    return dotted(minus(value.formatted(style)), locale: locale)
  }

  /// A value with at most `digits` significant digits, never grouped.
  package static func significant(_ value: Double, locale: Locale, digits: Int) -> String {
    let style = FloatingPointFormatStyle<Double>.number.locale(locale).grouping(.never)
      .precision(.significantDigits(1...max(1, digits)))
    return dotted(minus(value.formatted(style)), locale: locale)
  }

  /// `text`, a number Foundation wrote in `locale`, with a dot as its decimal mark: where the
  /// locale writes a comma (fr, de…), its dots can only be group marks and become U+202F first,
  /// so « 1.234,5 » reads « 1 234.5 », never 1.2345.
  package static func dotted(_ text: String, locale: Locale) -> String {
    let mark = locale.decimalSeparator ?? "."
    guard mark != "." else { return text }
    return text.replacing(".", with: "\u{202f}").replacing(mark, with: ".")
  }

  /// A typed number, `nil` unless the WHOLE text is one finite decimal number (R2: a field never
  /// applies a prefix the user did not mean).
  ///
  /// A dot is the decimal mark everywhere (the app never writes a dot between groups), and so is a
  /// comma typed by habit, unless the locale's region groups with a comma (en_US): there a comma is
  /// only a group mark, « 1,000 » is 1000 and « 1,5 » is refused rather than read as 15. Group marks (spaces, the locale's)
  /// count only in the integer part and in threes; surrounding whitespace is ignored; either minus.
  package static func parse(_ text: String, locale: Locale) -> Double? {
    let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacing("\u{2212}", with: "-")
    let commaGroups = locale.groupingSeparator == ","
    let marks = Set(typed.filter { $0 == "." || (!commaGroups && $0 == ",") })
    guard marks.count <= 1 else { return nil }
    let parts = typed.split(
      separator: marks.first ?? ".", maxSplits: 1, omittingEmptySubsequences: false)
    guard let integer = parts.first.map(String.init),
      let whole = ungrouped(integer, locale: locale)
    else { return nil }
    let plain = parts.count > 1 ? whole + "." + parts[1] : whole
    guard plain.wholeMatch(of: /[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?/) != nil,
      let value = Double(plain), value.isFinite
    else { return nil }
    return value
  }

  /// The integer part of a typed number without its group marks, or `nil` when they do not
  /// group it in threes after a non-zero lead (« 1 5 » is not 15, en « 0,115 » not 115).
  private static func ungrouped(_ integer: String, locale: Locale) -> String? {
    var groups: Set<Character> = [" ", "\u{a0}", "\u{202f}", "\u{2009}"]
    if let mark = locale.groupingSeparator, mark.count == 1, let group = mark.first, group != "." {
      groups.insert(group)
      if group == "'" { groups.insert("\u{2019}") }
    }
    guard integer.contains(where: groups.contains) else { return integer }
    let spaced = String(integer.map { groups.contains($0) ? " " : $0 })
    guard spaced.wholeMatch(of: /[+-]?[1-9]\d{0,2}( \d{3})+/) != nil else { return nil }
    return spaced.replacing(" ", with: "")
  }

  /// `text` with a leading `-` written as U+2212, the typographic minus.
  package static func minus(_ text: String) -> String {
    text.hasPrefix("-") ? "\u{2212}" + text.dropFirst() : text
  }
}
