import AstroStackApp
import Foundation
import ProcessKit
import Testing

/// Astronomy values as a French and an English astrophotographer read them.
@Suite("AstroFormat — exposures, integration, temperatures, sky, counts, exact parameters")
struct AstroFormatTests {
  static let french = AstroFormat(locale: Locale(identifier: "fr_FR"))
  static let english = AstroFormat(locale: Locale(identifier: "en_US"))
  static let space = "\u{a0}"

  struct Row: Sendable, CustomTestStringConvertible {
    let name: String
    let text: @Sendable (AstroFormat) -> String
    let french: String
    let english: String
    var testDescription: String { name }
  }

  nonisolated static let rows: [Row] = [
    Row(name: "300 s", text: { $0.exposure(ms: 300_000) }, french: "300 s", english: "300 s"),
    Row(name: "0.5 s", text: { $0.exposure(ms: 500) }, french: "0,5 s", english: "0.5 s"),
    Row(name: "5 ms", text: { $0.exposure(ms: 5) }, french: "5 ms", english: "5 ms"),
    Row(name: "2.5 s", text: { $0.exposure(ms: 2500) }, french: "2,5 s", english: "2.5 s"),
    Row(name: "no exposure", text: { $0.exposure(ms: 0) }, french: "—", english: "—"),
    Row(
      name: "20 880 s integration", text: { $0.integration(seconds: 20_880) },
      french: "5 h 48 min", english: "5 h 48 min"),
    Row(
      name: "45 min integration", text: { $0.integration(seconds: 2700) }, french: "45 min",
      english: "45 min"),
    Row(
      name: "45 s integration", text: { $0.integration(seconds: 45) }, french: "45 s",
      english: "45 s"),
    Row(
      name: "59.5 s in ms rounds up", text: { $0.integration(ms: 59_500) }, french: "1 min",
      english: "1 min"),
    Row(
      name: "1.4 s in ms rounds down", text: { $0.integration(ms: 1400) }, french: "1 s",
      english: "1 s"),
    Row(
      name: "−20 °C", text: { $0.temperature(celsius: -20) }, french: "−20 °C", english: "−20 °C"),
    Row(name: "0.115", text: { $0.parameter(0.115) }, french: "0,115", english: "0.115"),
    Row(name: "1 400 ADU", text: { $0.adu(1400) }, french: "1 400 ADU", english: "1,400 ADU"),
    Row(
      name: "FWHM with scale", text: { $0.fwhm(px: 2.34, arcsecPerPx: 1.8) },
      french: "2,3 px (4,2″)", english: "2.3 px (4.2″)"),
    Row(name: "3 σ", text: { $0.sigma(3) }, french: "3,0 σ", english: "3.0 σ"),
    Row(
      name: "RA 00h42m44s", text: { $0.rightAscension(degrees: 10.684_708) },
      french: "00h42m44,3s", english: "00h42m44.3s"),
    Row(
      name: "Dec +41°16′", text: { $0.declination(degrees: 41.268_75) },
      french: "+41°16′08″", english: "+41°16′08″"),
    Row(name: "1 light", text: { $0.lights(1) }, french: "1 brute", english: "1 light"),
    Row(name: "36 lights", text: { $0.lights(36) }, french: "36 brutes", english: "36 lights"),
    Row(name: "1 frame", text: { $0.frames(1) }, french: "1 pose", english: "1 frame"),
  ]

  /// The table's spaces are written as plain spaces: a unit and a group are separated by a
  /// no-break (U+00A0) or a narrow no-break (U+202F, French grouping) space.
  static func plain(_ text: String) -> String {
    text.replacing(space, with: " ").replacing("\u{202f}", with: " ")
  }

  @Test("each value reads as a French and an English astronomer write it", arguments: rows)
  func testFormats(_ row: Row) {
    #expect(Self.plain(row.text(Self.french)) == row.french)
    #expect(Self.plain(row.text(Self.english)) == row.english)
  }

  @Test("a unit never wraps away from its number")
  func testUnitsKeepTheirNumber() {
    #expect(Self.french.exposure(ms: 300_000) == "300\u{a0}s")
    #expect(Self.french.temperature(celsius: -20).hasPrefix("\u{2212}"))
  }

  /// Every bound and default of the shipped knobs, plus the PO-validated finishing values.
  static var knobValues: [Double] {
    let specs = (try? ProcessRegistry.standard().types.flatMap { $0.schema.specs }) ?? []
    let numbers = specs.flatMap { spec -> [Double] in
      guard case .number(let value, let bounds) = spec.kind else { return [] }
      return [value, bounds.lowerBound, bounds.upperBound]
    }
    return numbers + [0.115, 0.95, 0.00084, 0.00118, 0.25, 0.62, 1e-7, 123_456.5, -2.8, 1 / 3.0]
  }

  @Test("a parameter field reads back exactly the value it shows, in fr and en")
  func testParameterRoundTripIsExact() {
    #expect(Self.knobValues.count > 10)
    for format in [Self.french, Self.english] {
      for value in Self.knobValues {
        let text = format.parameter(value)
        #expect(format.parameter(parsing: text) == value, "\(value) → \(text)")
        #expect(!text.contains(" ") && !text.contains("\u{202f}"), "never grouped: \(text)")
      }
    }
    #expect(Self.french.parameter(parsing: "\u{2212}2,8") == -2.8)
    #expect(Self.french.parameter(parsing: "abc") == nil)
  }

  @Test(
    "a field that is not wholly a number in the locale is refused, never read as its prefix",
    arguments: [
      ("fr_FR", "0.115"), ("fr_FR", "1.5"), ("en_US", "1,5"), ("fr_FR", "2,8abc"), ("fr_FR", ""),
      ("en_US", " "),
    ])
  func testPartialInputIsRefused(locale: String, text: String) {
    #expect(AstroFormat(locale: Locale(identifier: locale)).parameter(parsing: text) == nil)
  }
}
