/// The localisation gate (card 0073): what makes a catalog, or a source it serves, unfit to ship.
package enum CatalogAudit {
  /// Argument labels whose literal is code, not text a user reads.
  package static let codeLabels: Set<String> = [
    "systemImage", "systemName", "verbatim", "named", "subsystem", "category", "forKey",
    "forResource", "withExtension", "identifier", "id", "suiteName",
  ]

  /// Every violation of `catalog`: languages, translation state, format specifiers, and — when
  /// `used` is given — keys whose shape (`LiteralShape`) no source produces any more.
  package static func violations(
    of catalog: StringCatalog, used: Set<String>? = nil
  ) -> [CatalogViolation] {
    var found: [CatalogViolation] = []
    if catalog.sourceLanguage != "en" { found.append(.sourceLanguage(catalog.sourceLanguage)) }
    for key in catalog.strings.keys.sorted() {
      let localizations = catalog.strings[key]?.localizations ?? [:]
      for language in StringCatalog.languages {
        guard let localization = localizations[language] else {
          found.append(.missing(key: key, language: language))
          continue
        }
        found += violations(of: localization, key: key, language: language)
      }
      if let used, !used.contains(LiteralShape.ofKey(key)) { found.append(.stale(key: key)) }
    }
    return found
  }

  /// The shapes of the literals of `sources`: what `violations(of:used:)` checks keys against.
  package static func usedShapes(in sources: [String]) -> Set<String> {
    Set(sources.flatMap(SourceLiterals.of).map { LiteralShape.ofLiteral($0.content) })
  }

  /// The literals of `source` a user would read that are not keys of `catalog`.
  ///
  /// Such a literal shows in English whatever the language. Literals without a letter (`—`,
  /// `\(count)`) and literals passed to a code label (`systemImage:`) are not text.
  package static func uncatalogued(
    in source: String, file: String, catalog: StringCatalog
  ) -> [CatalogViolation] {
    let keys = Set(catalog.strings.keys.map(LiteralShape.ofKey))
    return SourceLiterals.of(source).compactMap { literal in
      let shape = LiteralShape.ofLiteral(literal.content)
      let isText = shape.replacing(LiteralShape.hole, with: "").contains(where: \.isLetter)
      guard isText, !codeLabels.contains(literal.label ?? ""), !keys.contains(shape) else {
        return nil
      }
      return .uncatalogued(literal: literal.content, file: file, line: literal.line)
    }
  }

  // MARK: - One localization

  private static func violations(
    of localization: StringCatalog.Localization, key: String, language: String
  ) -> [CatalogViolation] {
    let expected = FormatSpecifiers.of(key)
    if let variations = localization.variations {
      return violations(of: variations, key: key, language: language, expected: expected)
    }
    guard let unit = localization.stringUnit else {
      return [.missing(key: key, language: language)]
    }
    var found: [CatalogViolation] = []
    if unit.state != "translated" || unit.value.isEmpty {
      found.append(.untranslated(key: key, language: language))
    }
    let specifiers = FormatSpecifiers.of(unit.value)
    if specifiers != expected {
      found.append(
        .formatMismatch(key: key, language: language, expected: expected, found: specifiers))
    }
    return found
  }

  /// Plurals of one number: an `other` case, and no variant reading another argument.
  private static func violations(
    of variations: StringCatalog.Variations, key: String, language: String, expected: [String]
  ) -> [CatalogViolation] {
    var found = variations.unsupported.map {
      CatalogViolation.unsupported(key: key, language: language, reason: "\($0) variations")
    }
    guard let plural = variations.plural else {
      // Nothing to compile: the key would show in English.
      return found.isEmpty ? [.missing(key: key, language: language)] : found
    }
    if expected.count != 1 {
      found.append(
        .unsupported(key: key, language: language, reason: "plural of \(expected.count) numbers"))
    }
    if plural["other"] == nil {
      found.append(.unsupported(key: key, language: language, reason: "plural without other"))
    }
    for category in plural.keys.sorted() {
      guard let unit = plural[category]?.stringUnit else { continue }
      if unit.state != "translated" || unit.value.isEmpty {
        found.append(.untranslated(key: key, language: "\(language).\(category)"))
      }
      // A variant may leave the number out (« une seule brute »), never read another one.
      let specifiers = FormatSpecifiers.of(unit.value)
      if !specifiers.isEmpty, specifiers != expected {
        found.append(
          .formatMismatch(
            key: key, language: "\(language).\(category)", expected: expected, found: specifiers))
      }
    }
    return found
  }
}
