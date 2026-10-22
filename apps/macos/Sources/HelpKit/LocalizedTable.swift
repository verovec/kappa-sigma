package import Foundation

/// One JSON file per locale, id → `Value`.
///
/// `<root>/<locale>/<file>`: the loader and the gate shapes `Glossary` and `ParamDocs` share
/// (card 0086). A missing or malformed locale is an empty table that the gate reports.
package struct LocalizedTable<Value: Decodable & Sendable>: Sendable {
  /// The file name, named by the gate.
  package let file: String
  private let entries: [String: [String: Value]]

  /// The tables `<root>/<locale>/<file>`, one per `HelpIndex.locales`.
  package init(root: URL, file: String) {
    var entries: [String: [String: Value]] = [:]
    for locale in HelpIndex.locales {
      let url = root.appendingPathComponent(locale).appendingPathComponent(file)
      let data = try? Data(contentsOf: url)
      entries[locale] = data.flatMap { try? JSONDecoder().decode([String: Value].self, from: $0) }
    }
    self.entries = entries
    self.file = file
  }

  /// The entry `id` in `locale`, or `nil`.
  package func entry(_ id: String, locale: String) -> Value? {
    entries[locale]?[id]
  }

  /// One sentence per gate failure: an unreadable locale, an id missing from a locale (named a
  /// `kind`), or what `check` finds wrong with an entry.
  package func problems(ids: [String], kind: String, check: (Value) -> [String]) -> [String] {
    HelpIndex.locales.flatMap { locale -> [String] in
      guard let table = entries[locale] else { return ["\(locale): no readable \(file)"] }
      return ids.flatMap { id -> [String] in
        guard let value = table[id] else { return ["\(id): no \(locale) \(kind)"] }
        return check(value).map { "\(id) (\(locale)): \($0)" }
      }
    }
  }

  /// The ids of the `locale` file that `ids` does not name: entries nothing uses any more.
  package func stale(ids: [String], locale: String) -> [String] {
    Set(entries[locale]?.keys.map { $0 } ?? []).subtracting(ids).sorted()
  }
}
