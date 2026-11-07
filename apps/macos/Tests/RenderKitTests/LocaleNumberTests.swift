import Foundation
import RenderKit
import Testing

/// Every number on screen reads with a dot, whatever the interface language (PO 07/11
/// « point partout »), and a field takes either mark, so a comma typed by habit still works.
@Suite("LocaleNumber — a dot in every language, either mark typed")
struct LocaleNumberTests {
  struct Row: Sendable, CustomTestStringConvertible {
    let locale: String
    let integer: String
    let decimal: String
    let grouped: String
    let significant: String
    var testDescription: String { locale }
  }

  /// 12 345, 1234.5 (1 digit), 1234.5 grouped, 0.0076334 (3 significant digits). Spaces are plain
  /// here: `plain` folds the no-break ones a locale groups with.
  static let rows: [Row] = [
    Row(
      locale: "fr_FR", integer: "12 345", decimal: "1234.5", grouped: "1 234.5",
      significant: "0.00763"),
    Row(
      locale: "en_US", integer: "12,345", decimal: "1234.5", grouped: "1,234.5",
      significant: "0.00763"),
    Row(
      locale: "de_DE", integer: "12 345", decimal: "1234.5", grouped: "1 234.5",
      significant: "0.00763"),
    Row(
      locale: "fr_CH", integer: "12'345", decimal: "1234.5", grouped: "1'234.5",
      significant: "0.00763"),
  ]

  static func plain(_ text: String) -> String {
    text.replacing("\u{a0}", with: " ").replacing("\u{202f}", with: " ")
  }

  @Test("the decimal mark is a dot and a group is never a dot", arguments: rows)
  func testDottedWritesTheDotInEveryLocale(_ row: Row) {
    let locale = Locale(identifier: row.locale)
    #expect(Self.plain(LocaleNumber.integer(12_345, locale: locale)) == row.integer)
    #expect(
      Self.plain(LocaleNumber.decimal(1234.5, locale: locale, maxFractionDigits: 1)) == row.decimal)
    #expect(
      Self.plain(LocaleNumber.decimal(1234.5, locale: locale, maxFractionDigits: 1, grouping: true))
        == row.grouped)
    let significant = LocaleNumber.significant(0.007_633_4, locale: locale, digits: 3)
    #expect(Self.plain(significant) == row.significant)
    #expect(LocaleNumber.decimal(-0.25, locale: locale, maxFractionDigits: 2) == "\u{2212}0.25")
  }

  @Test(
    "a typed number takes a dot or a comma as its mark, and nothing but a whole number",
    arguments: zip(
      [
        "0,115", "0.115", "\u{2212}2,8", "-2.8", "1 234.5", "1\u{202f}234,5", " 3 ", "+1.5",
        "1.234,5", "1,234.5", "0.1.2", "2,8abc", "", " ", "abc", "nan", "inf", "0x10",
      ],
      [
        0.115, 0.115, -2.8, -2.8, 1234.5, 1234.5, 3, 1.5,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
      ] as [Double?]))
  func testParseAcceptsEitherMarkAndRefusesTheRest(text: String, expected: Double?) {
    for locale in ["fr_FR", "en_US", "de_DE"] {
      #expect(LocaleNumber.parse(text, locale: Locale(identifier: locale)) == expected, "\(locale)")
    }
  }

  /// Ungrouped, as a field writes it (a grouped en « 1,234.5 » carries both marks: refused).
  @Test("what a field writes parses back to the identical value, in every locale")
  func testWrittenReadsBack() {
    let values = [0.115, -2.8, 0.25, 1e-7, 123_456.5, 0]
    for identifier in ["fr_FR", "en_US", "de_DE", "fr_CH"] {
      let locale = Locale(identifier: identifier)
      for value in values {
        let text = LocaleNumber.decimal(value, locale: locale, maxFractionDigits: 7)
        #expect(LocaleNumber.parse(text, locale: locale) == value, "\(identifier): \(text)")
      }
    }
  }
}
