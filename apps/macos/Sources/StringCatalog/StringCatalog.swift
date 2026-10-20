package import Foundation

/// A `Localizable.xcstrings` string catalog: the source of every UI string of a target.
///
/// Only the subset the house uses is modelled: a `stringUnit` per language, or `plural`
/// variations of one number. Anything else is reported by `CatalogAudit` and refused by the
/// compiler, so the build never ships a string it cannot resolve.
package struct StringCatalog: Decodable, Equatable, Sendable {
  /// The languages every key must carry (E20: development language `en`, French complete).
  package static let languages = ["en", "fr"]

  /// The development language of the keys (`en`).
  package var sourceLanguage: String
  /// Every key with its localizations.
  package var strings: [String: Entry]

  /// One key: a localization per language.
  package struct Entry: Decodable, Equatable, Sendable {
    /// The translator's note.
    package var comment: String?
    /// The key's value per language code (`nil` when the key has none yet).
    package var localizations: [String: Localization]?
  }

  /// A key in one language: a plain string, or plural variations.
  package struct Localization: Decodable, Equatable, Sendable {
    /// The plain value.
    package var stringUnit: StringUnit?
    /// The variants, when the value depends on a number.
    package var variations: Variations?
  }

  /// Variations of a localization; only `plural` is supported.
  package struct Variations: Decodable, Equatable, Sendable {
    /// The variants by CLDR plural category (`one`, `other`…).
    package var plural: [String: Variant]?
    /// Kinds the house does not support (`device`, `width`…): reported, never compiled.
    package var unsupported: [String]

    private struct AnyKey: CodingKey {
      var stringValue: String
      var intValue: Int? { nil }
      init(stringValue: String) { self.stringValue = stringValue }
      init?(intValue: Int) { nil }
    }

    package init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: AnyKey.self)
      plural = try container.decodeIfPresent(
        [String: Variant].self, forKey: AnyKey(stringValue: "plural"))
      unsupported = container.allKeys.map(\.stringValue).filter { $0 != "plural" }.sorted()
    }
  }

  /// One plural category.
  package struct Variant: Decodable, Equatable, Sendable {
    /// The category's value.
    package var stringUnit: StringUnit
  }

  /// A translated value and its review state.
  package struct StringUnit: Decodable, Equatable, Sendable {
    /// `translated` once reviewed; anything else fails the gate.
    package var state: String
    /// The text, with the key's format specifiers.
    package var value: String
  }

  /// Decodes the JSON of an `.xcstrings` file.
  package init(data: Data) throws {
    self = try JSONDecoder().decode(Self.self, from: data)
  }

  /// Reads the `.xcstrings` file at `url`.
  package init(contentsOf url: URL) throws {
    try self.init(data: Data(contentsOf: url))
  }
}
