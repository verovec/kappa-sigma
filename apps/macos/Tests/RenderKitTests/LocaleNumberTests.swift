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

  struct Typed: Sendable, CustomTestStringConvertible {
    let text: String
    let french: Double?
    let english: Double?
    let german: Double?
    var testDescription: String { "« \(text) »" }
  }

  /// fr_FR and de_DE write a comma as their decimal mark: typed by habit, it is one. en_US groups
  /// with a comma: there a comma is only a group mark, and a text it cannot group is refused
  /// rather than read 1000 times too small. Spaces group in every locale, in threes only.
  static let typed: [Typed] = [
    Typed(text: "0.115", french: 0.115, english: 0.115, german: 0.115),
    Typed(text: "0,115", french: 0.115, english: nil, german: 0.115),
    Typed(text: "\u{2212}2,8", french: -2.8, english: nil, german: -2.8),
    Typed(text: "-2.8", french: -2.8, english: -2.8, german: -2.8),
    Typed(text: "+1.5", french: 1.5, english: 1.5, german: 1.5),
    Typed(text: "1,000", french: 1, english: 1000, german: 1),
    Typed(text: "1,234.5", french: nil, english: 1234.5, german: nil),
    Typed(text: "1.234,5", french: nil, english: nil, german: nil),
    Typed(text: "1 234.5", french: 1234.5, english: 1234.5, german: 1234.5),
    Typed(text: "1\u{202f}234,5", french: 1234.5, english: nil, german: 1234.5),
    Typed(text: " 3 ", french: 3, english: 3, german: 3),
    Typed(text: "0.5\t", french: 0.5, english: 0.5, german: 0.5),
    Typed(text: "1 5", french: nil, english: nil, german: nil),
    Typed(text: "0.1 25", french: nil, english: nil, german: nil),
    Typed(text: "0.1.2", french: nil, english: nil, german: nil),
    Typed(text: "2,8abc", french: nil, english: nil, german: nil),
    Typed(text: "", french: nil, english: nil, german: nil),
    Typed(text: " ", french: nil, english: nil, german: nil),
    Typed(text: "abc", french: nil, english: nil, german: nil),
    Typed(text: "nan", french: nil, english: nil, german: nil),
    Typed(text: "inf", french: nil, english: nil, german: nil),
    Typed(text: "0x10", french: nil, english: nil, german: nil),
  ]

  @Test(
    "a typed number takes the habit's comma where it is a decimal mark, and only whole numbers",
    arguments: typed)
  func testParseAcceptsEitherMarkAndRefusesTheRest(_ row: Typed) {
    #expect(LocaleNumber.parse(row.text, locale: Locale(identifier: "fr_FR")) == row.french)
    #expect(LocaleNumber.parse(row.text, locale: Locale(identifier: "en_US")) == row.english)
    #expect(LocaleNumber.parse(row.text, locale: Locale(identifier: "de_DE")) == row.german)
  }

  @Test("Swiss grouping takes the typed apostrophe and the typographic one")
  func testSwissApostrophes() {
    let swiss = Locale(identifier: "fr_CH")
    #expect(LocaleNumber.parse("1'234.5", locale: swiss) == 1234.5)
    #expect(LocaleNumber.parse("1\u{2019}234.5", locale: swiss) == 1234.5)
    #expect(LocaleNumber.parse("1\u{2019}23", locale: swiss) == nil)
  }

  /// Ungrouped, as a field writes it.
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
