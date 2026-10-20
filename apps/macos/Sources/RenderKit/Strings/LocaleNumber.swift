package import Foundation

/// Numbers written in a locale, the one core the viewer and the app's `AstroFormat` share
/// (card 0074): Foundation `FormatStyle`, a U+2212 minus, the locale's decimal mark.
package enum LocaleNumber {
  /// An integer with the locale's grouping (`20 880`, `20,880`).
  package static func integer(_ value: Int, locale: Locale) -> String {
    minus(value.formatted(.number.locale(locale)))
  }

  /// A decimal with `minFractionDigits`…`maxFractionDigits` digits after the mark.
  package static func decimal(
    _ value: Double, locale: Locale, maxFractionDigits: Int, minFractionDigits: Int = 0,
    grouping: Bool = false
  ) -> String {
    let style = FloatingPointFormatStyle<Double>.number.locale(locale)
      .precision(.fractionLength(minFractionDigits...max(minFractionDigits, maxFractionDigits)))
      .grouping(grouping ? .automatic : .never)
    return minus(value.formatted(style))
  }

  /// A value with at most `digits` significant digits, never grouped.
  package static func significant(_ value: Double, locale: Locale, digits: Int) -> String {
    let style = FloatingPointFormatStyle<Double>.number.locale(locale).grouping(.never)
      .precision(.significantDigits(1...max(1, digits)))
    return minus(value.formatted(style))
  }

  /// `text` with a leading `-` written as U+2212, the typographic minus.
  package static func minus(_ text: String) -> String {
    text.hasPrefix("-") ? "\u{2212}" + text.dropFirst() : text
  }

  /// The `.` decimal marks of `text` written in the locale's own mark, as in `00h42m44,3s`.
  package static func decimalMark(_ text: String, locale: Locale) -> String {
    let mark = locale.decimalSeparator ?? "."
    return mark == "." ? text : text.replacing(".", with: mark)
  }
}
