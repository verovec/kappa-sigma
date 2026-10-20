/// One way a string catalog, or the sources it serves, breaks the localisation rules.
package enum CatalogViolation: Equatable, Sendable, CustomStringConvertible {
  /// The catalog is not authored in English (E20 decision).
  case sourceLanguage(String)
  /// A key has no value in a required language.
  case missing(key: String, language: String)
  /// A value is empty or not marked `translated`.
  case untranslated(key: String, language: String)
  /// A value's format specifiers differ from the key's: the app would read the wrong argument.
  case formatMismatch(key: String, language: String, expected: [String], found: [String])
  /// A feature the compiler does not support (device variations, plurals of several numbers…).
  case unsupported(key: String, language: String, reason: String)
  /// A key no source of the target uses any more.
  case stale(key: String)
  /// A user-facing literal of a source that is not a catalog key (it would show in English).
  case uncatalogued(literal: String, file: String, line: Int)

  package var description: String {
    switch self {
    case .sourceLanguage(let language): "source language is \(language), not en"
    case .missing(let key, let language): "\"\(key)\" has no \(language) value"
    case .untranslated(let key, let language): "\"\(key)\" is not translated in \(language)"
    case .formatMismatch(let key, let language, let expected, let found):
      "\"\(key)\" in \(language): specifiers \(found), expected \(expected)"
    case .unsupported(let key, let language, let reason): "\"\(key)\" in \(language): \(reason)"
    case .stale(let key): "\"\(key)\" is used by no source"
    case .uncatalogued(let literal, let file, let line):
      "\(file):\(line): \"\(literal)\" is not in the catalog"
    }
  }
}
