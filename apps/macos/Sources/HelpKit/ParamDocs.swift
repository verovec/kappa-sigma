package import Foundation

/// The one-line definition of every process parameter (card 0086).
///
/// `<root>/<locale>/params.json`, `<process id>.<parameter id>` → definition. The parameter's
/// title is ProcessKit's catalog; only the words a « ? » adds live here, so no title is declared
/// twice.
package struct ParamDocs: Sendable {
  /// The file, per locale.
  package static let file = "params.json"

  private let table: LocalizedTable<String>

  /// The docs `<root>/<locale>/params.json`, one per `HelpIndex.locales`; a missing or malformed
  /// locale is empty and the gate reports it.
  package init(root: URL) {
    table = LocalizedTable(root: root, file: Self.file)
  }

  /// The definition of `id` (`<process>.<param>`) in `locale`, or `nil`.
  package func definition(_ id: String, locale: String) -> String? {
    table.entry(id, locale: locale)
  }

  /// One sentence per gate failure: an unreadable locale, an id missing from a locale, a
  /// definition longer than a line (`Glossary.maxDefinitionWords`).
  package func problems(ids: [String]) -> [String] {
    table.problems(ids: ids, kind: "definition", check: Glossary.definitionProblems)
  }

  /// The ids of the `locale` file that `ids` does not name: parameters that no longer exist.
  package func stale(ids: [String], locale: String) -> [String] {
    table.stale(ids: ids, locale: locale)
  }
}
