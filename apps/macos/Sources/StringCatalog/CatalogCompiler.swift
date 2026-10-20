package import Foundation

/// Compiles a string catalog into the `<language>.lproj/Localizable.strings` and
/// `Localizable.stringsdict` Foundation reads.
///
/// SwiftPM copies an `.xcstrings` resource as is when the toolchain has no `xcstringstool`
/// (Command Line Tools), and the app would then show its keys in every language: the
/// `CatalogPlugin` build tool runs this on every host instead, so CLT and Xcode builds ship the
/// same tables.
package enum CatalogCompiler {
  /// The two tables of one language.
  package struct Tables: Equatable, Sendable {
    /// `"key" = "value";` lines, sorted by key.
    package var strings: String
    /// A property list of the plural keys (an empty dictionary when there are none).
    package var stringsdict: Data
  }

  /// Why a catalog cannot be compiled: the gate's violations (`CatalogAudit`).
  package struct Failure: Error, CustomStringConvertible {
    /// What the gate refused.
    package var violations: [CatalogViolation]

    /// A failure listing `violations`.
    package init(violations: [CatalogViolation]) {
      self.violations = violations
    }
    /// One violation per line, as the build log shows them.
    package var description: String { violations.map(\.description).joined(separator: "\n") }
  }

  /// The tables of `language`; a key without a value in it falls back to the key at runtime.
  package static func tables(of catalog: StringCatalog, language: String) throws -> Tables {
    var lines: [String] = []
    var plurals: [String: Any] = [:]
    for key in catalog.strings.keys.sorted() {
      guard let localization = catalog.strings[key]?.localizations?[language] else { continue }
      if let plural = localization.variations?.plural {
        plurals[key] = pluralRule(plural, key: key)
      } else if let unit = localization.stringUnit {
        lines.append("\(quoted(key)) = \(quoted(unit.value));")
      }
    }
    let dictionary = try PropertyListSerialization.data(
      fromPropertyList: plurals, format: .xml, options: 0)
    return Tables(strings: lines.map { $0 + "\n" }.joined(), stringsdict: dictionary)
  }

  /// Writes `<language>.lproj/Localizable.{strings,stringsdict}` under `folder` for every
  /// required language, after the gate (languages and specifiers) has passed.
  package static func compile(_ catalog: StringCatalog, into folder: URL) throws {
    let violations = CatalogAudit.violations(of: catalog)
    guard violations.isEmpty else { throw Failure(violations: violations) }
    for language in StringCatalog.languages {
      let tables = try tables(of: catalog, language: language)
      let lproj = folder.appendingPathComponent("\(language).lproj", isDirectory: true)
      try FileManager.default.createDirectory(at: lproj, withIntermediateDirectories: true)
      try Data(tables.strings.utf8).write(
        to: lproj.appendingPathComponent("Localizable.strings"), options: .atomic)
      try tables.stringsdict.write(
        to: lproj.appendingPathComponent("Localizable.stringsdict"), options: .atomic)
    }
  }

  /// The stringsdict rule of a key whose single number picks the variant.
  private static func pluralRule(
    _ plural: [String: StringCatalog.Variant], key: String
  ) -> [String: Any] {
    let specifier = FormatSpecifiers.of(key).first ?? "%lld"
    var rule: [String: Any] = [
      "NSStringFormatSpecTypeKey": "NSStringPluralRuleType",
      "NSStringFormatValueTypeKey": String(specifier.dropFirst()),
    ]
    for (category, variant) in plural { rule[category] = variant.stringUnit.value }
    return ["NSStringLocalizedFormatKey": "%#@count@", "count": rule]
  }

  /// A `.strings` literal: quotes, backslashes and line breaks escaped.
  private static func quoted(_ text: String) -> String {
    var escaped = ""
    for char in text {
      switch char {
      case "\\": escaped += "\\\\"
      case "\"": escaped += "\\\""
      case "\n": escaped += "\\n"
      case "\t": escaped += "\\t"
      default: escaped.append(char)
      }
    }
    return "\"\(escaped)\""
  }
}
