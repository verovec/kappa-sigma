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
  /// A dot or a comma is the decimal mark (a comma typed by habit still works); spaces and the
  /// locale's other group marks are ignored; either minus. A text with both marks is refused:
  /// « 1.234,5 » or « 1,234.5 » cannot be read one way only.
  package static func parse(_ text: String, locale: Locale) -> Double? {
    var plain = text.replacing("\u{2212}", with: "-")
    for space in [" ", "\u{a0}", "\u{202f}"] { plain = plain.replacing(space, with: "") }
    if let group = locale.groupingSeparator, ![".", ","].contains(group) {
      plain = plain.replacing(group, with: "")
    }
    guard !(plain.contains(".") && plain.contains(",")) else { return nil }
    plain = plain.replacing(",", with: ".")
    guard plain.wholeMatch(of: /[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?/) != nil,
      let value = Double(plain), value.isFinite
    else { return nil }
    return value
  }

  /// `text` with a leading `-` written as U+2212, the typographic minus.
  package static func minus(_ text: String) -> String {
    text.hasPrefix("-") ? "\u{2212}" + text.dropFirst() : text
  }
}
