package import Foundation
internal import RenderKit

/// How the app writes astronomy values in a locale (card 0074): « 0,115 », « 5 h 48 min »,
/// « −20 °C », « 36 brutes ».
///
/// Values only: what to show is decided elsewhere. Numbers go through Foundation `FormatStyle`
/// in `locale` (decimal comma, grouping), words through the app's catalog in the same locale.
/// A unit is separated by a no-break space; negatives use U+2212.
package nonisolated struct AstroFormat: Sendable {
  /// The view's locale (`\.locale`, set to `AppLocale.interface` at the window roots).
  package let locale: Locale

  /// Formats in `locale`.
  package init(locale: Locale) {
    self.locale = locale
  }

  private static let space = "\u{a0}"

  // MARK: - Times

  /// An exposure: `300 s`, `0,5 s` (short flats), `5 ms` below a tenth of a second; `—` when
  /// the type has none.
  package func exposure(ms: Int) -> String {
    guard ms > 0 else { return "—" }
    guard ms >= 100 else { return integer(ms) + Self.space + "ms" }
    return decimal(Double(ms) / 1000, maxFractionDigits: 3) + Self.space + "s"
  }

  /// A total integration time: `5 h 48 min`, `12 min`, `45 s`.
  /// An integration given in milliseconds, rounded to the second (never truncated: sub-second
  /// exposures still add up).
  package func integration(ms: Int) -> String {
    integration(seconds: Int((Double(ms) / 1000).rounded()))
  }

  package func integration(seconds: Int) -> String {
    let (hours, minutes) = (seconds / 3600, seconds / 60 % 60)
    if hours > 0 {
      return integer(hours) + Self.space + "h" + Self.space + integer(minutes) + Self.space + "min"
    }
    if minutes > 0 { return integer(minutes) + Self.space + "min" }
    return integer(seconds) + Self.space + "s"
  }

  // MARK: - Sensor

  /// A sensor temperature: `−20 °C`.
  package func temperature(celsius: Int) -> String {
    integer(celsius) + Self.space + "°C"
  }

  /// A level in ADU: `1 400 ADU`.
  package func adu(_ value: Double) -> String {
    decimal(value, maxFractionDigits: 0, grouping: true) + Self.space + "ADU"
  }

  /// A star size: `2,3 px`, with arcseconds when the image scale is known (`2,3 px (4,1″)`).
  package func fwhm(px: Double, arcsecPerPx scale: Double? = nil) -> String {
    let pixels = decimal(px, maxFractionDigits: 1, minFractionDigits: 1) + Self.space + "px"
    guard let scale else { return pixels }
    return pixels + " (" + decimal(px * scale, maxFractionDigits: 1, minFractionDigits: 1) + "″)"
  }

  /// A rejection threshold: `3,0 σ`.
  package func sigma(_ value: Double) -> String {
    decimal(value, maxFractionDigits: 1, minFractionDigits: 1) + Self.space + "σ"
  }

  // MARK: - Sky

  /// Right ascension, `00h42m44,3s` (the viewer's sexagesimal, in the locale's decimal mark).
  package func rightAscension(degrees: Double) -> String {
    LocaleNumber.decimalMark(PixelReadout.Sky(ra: degrees, dec: 0).raText, locale: locale)
  }

  /// Declination, `+41°16′09″`.
  package func declination(degrees: Double) -> String {
    PixelReadout.Sky(ra: 0, dec: degrees).decText
  }

  // MARK: - Counts

  /// `1 brute`, `36 brutes` / `1 light`, `36 lights`.
  package func lights(_ count: Int) -> String {
    String(localized: .app("\(count) lights", locale: locale))
  }

  /// A scan's count: `1 234 / 3 480 fichiers lus` / `1,234 / 3,480 files read`.
  package func filesRead(_ done: Int, of total: Int) -> String {
    String(localized: .app("\(integer(done)) / \(integer(total)) files read", locale: locale))
  }

  /// `1 pose`, `36 poses` / `1 frame`, `36 frames`.
  package func frames(_ count: Int) -> String {
    var resource = Self.frameCount(count)
    resource.locale = locale
    return String(localized: resource)
  }

  /// The frame count as a catalog resource, for a sentence that nests it (it then takes the
  /// sentence's language): the ONE source of the « poses » plural.
  package static func frameCount(_ count: Int) -> LocalizedStringResource {
    .app("\(count) frames")
  }

  // MARK: - Numbers

  /// An integer with the locale's grouping and a U+2212 minus.
  package func integer(_ value: Int) -> String {
    LocaleNumber.integer(value, locale: locale)
  }

  /// A decimal with at most `maxFractionDigits` digits after the mark.
  package func decimal(
    _ value: Double, maxFractionDigits: Int, minFractionDigits: Int = 0, grouping: Bool = false
  ) -> String {
    LocaleNumber.decimal(
      value, locale: locale, maxFractionDigits: maxFractionDigits,
      minFractionDigits: minFractionDigits, grouping: grouping)
  }

  /// A measured value with at most `digits` significant digits (`0,0076334`).
  package func significant(_ value: Double, digits: Int) -> String {
    LocaleNumber.significant(value, locale: locale, digits: digits)
  }

  /// A percentage with two decimals, signed when positive: `+59,19 %`, `−3,33 %`.
  package func percent(_ value: Double) -> String {
    (value > 0 ? "+" : "") + decimal(value, maxFractionDigits: 2, minFractionDigits: 2)
      + Self.space + "%"
  }

  /// A parameter as a field shows it: the shortest digits that read back as exactly `value`
  /// (R2: the value applied is the value shown), in the locale's decimal mark, never grouped.
  package func parameter(_ value: Double) -> String {
    LocaleNumber.minus(value.formatted(Self.parameterStyle(value, locale: locale)))
  }

  /// The value a parameter field holds, or `nil` unless the WHOLE text is a number in `locale`
  /// (U+2212 or `-` for the sign): Foundation would read « 0.115 » in French as 0 and stop at
  /// the dot, which would apply a value the user never typed (R2).
  package func parameter(parsing text: String) -> Double? {
    let ascii = text.trimmingCharacters(in: .whitespaces).replacing("\u{2212}", with: "-")
    let style = FloatingPointFormatStyle<Double>.number.locale(locale).grouping(.never)
    guard !ascii.isEmpty,
      let (end, value) = try? style.consuming(
        ascii, startingAt: ascii.startIndex, in: ascii.startIndex..<ascii.endIndex),
      end == ascii.endIndex
    else { return nil }
    return value
  }

  /// Enough significant digits for the shortest form of `value` that reads back exactly.
  private static func parameterStyle(
    _ value: Double, locale: Locale
  ) -> FloatingPointFormatStyle<Double> {
    let mantissa = String(value.magnitude).split(separator: "e").first.map(String.init) ?? ""
    let digits = mantissa.filter(\.isNumber).drop { $0 == "0" }.count
    return .number.locale(locale).grouping(.never)
      .precision(.significantDigits(1...max(1, min(17, digits))))
  }
}
