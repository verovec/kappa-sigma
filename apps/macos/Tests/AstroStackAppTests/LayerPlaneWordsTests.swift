import AstroStackApp
import Foundation
import Testing

/// A layer token in words (card 0139): the switcher's words for a layer (glossary; a custom id
/// verbatim), « × » for a product, a plane by its colour.
@MainActor
@Suite("LayerPlaneWords — a layer token in the view's language")
struct LayerPlaneWordsTests {
  struct Words: CustomTestStringConvertible, Sendable {
    let token: String
    let locale: String
    let expected: String
    var testDescription: String { "\(token) (\(locale)) → \(expected)" }
  }

  nonisolated static let words: [Words] = [
    Words(token: "RGB.r", locale: "en", expected: "Broadband (RGB) · red"),
    Words(token: "RGB.r", locale: "fr", expected: "Large bande (RGB) · rouge"),
    Words(token: "RGB.b", locale: "fr", expected: "Large bande (RGB) · bleu"),
    Words(token: "Ha", locale: "en", expected: "Hydrogen-alpha"),
    Words(token: "Ha*OIII", locale: "fr", expected: "Hydrogène alpha × Oxygène III"),
    Words(token: "L", locale: "en", expected: "Luminance"),
    Words(token: "R", locale: "fr", expected: "Rouge"),
    Words(token: "NII-custom", locale: "fr", expected: "NII-custom"),
    Words(token: "none", locale: "en", expected: "None"),
    Words(token: "none", locale: "fr", expected: "Aucun"),
  ]

  @Test("testWords", arguments: words)
  func testWords(row: Words) {
    #expect(
      LayerPlaneWords.words(row.token, locale: Locale(identifier: row.locale)) == row.expected)
  }
}
