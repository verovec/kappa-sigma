package import Foundation

/// The one astronomy glossary (card 0074): a term id → its label and a one-line definition, in
/// every locale the app ships.
///
/// Entries are `<root>/<locale>/glossary.json`. Term ids are derived from the catalogs that own
/// the vocabulary (`FrameType`, `Filter`, `FilterSet`… in StackKit, the journey stages in the
/// app), never from a second list; HelpKit only holds the words, so it stays UI- and
/// StackKit-free.
package struct Glossary: Sendable {
  /// A term as one locale words it.
  package struct Term: Decodable, Equatable, Sendable {
    /// What a control or column shows (« Brutes », "Lights").
    package let label: String
    /// One line, for a tooltip.
    package let definition: String

    /// A term labelled `label`, defined by `definition`.
    package init(label: String, definition: String) {
      self.label = label
      self.definition = definition
    }
  }

  /// A definition's limit: read at a glance, in a tooltip.
  package static let maxDefinitionWords = 24

  private let terms: [String: [String: Term]]

  /// The glossaries under `root`, one per `HelpIndex.locales`; a missing or malformed locale is
  /// an empty glossary that the gate reports.
  package init(root: URL) {
    var terms: [String: [String: Term]] = [:]
    for locale in HelpIndex.locales {
      let url = root.appendingPathComponent(locale).appendingPathComponent("glossary.json")
      let data = try? Data(contentsOf: url)
      terms[locale] = data.flatMap { try? JSONDecoder().decode([String: Term].self, from: $0) }
    }
    self.terms = terms
  }

  /// HelpKit's glossary in `bundle` (the packaged app passes its resolved resource bundle).
  package init(bundle: Bundle) {
    self.init(root: bundle.resourceURL?.appendingPathComponent("Help") ?? bundle.bundleURL)
  }

  /// HelpKit's glossary as SwiftPM builds it (tests, `swift run`).
  package static var bundled: Self { Self(bundle: .module) }

  /// The term `id` in `locale` (`fr`, `en`), or `nil`.
  package func term(_ id: String, locale: String) -> Term? {
    terms[locale]?[id]
  }

  /// One sentence per gate failure: an unreadable locale, an id missing from a locale, an empty
  /// label, or a definition longer than a line.
  package func problems(ids: [String]) -> [String] {
    HelpIndex.locales.flatMap { locale -> [String] in
      guard let entries = terms[locale] else { return ["\(locale): no readable glossary.json"] }
      return ids.flatMap { id -> [String] in
        guard let term = entries[id] else { return ["\(id): no \(locale) term"] }
        return Self.problems(of: term).map { "\(id) (\(locale)): \($0)" }
      }
    }
  }

  /// The ids of the `locale` file that `ids` does not name: words no catalog uses any more.
  package func stale(ids: [String], locale: String) -> [String] {
    Set(terms[locale]?.keys.map { $0 } ?? []).subtracting(ids).sorted()
  }

  private static func problems(of term: Term) -> [String] {
    var problems: [String] = []
    if term.label.trimmingCharacters(in: .whitespaces).isEmpty { problems.append("empty label") }
    let words = term.definition.split(whereSeparator: \.isWhitespace).count
    if words == 0 || words > maxDefinitionWords || term.definition.contains("\n") {
      problems.append("definition of \(words) words, one line of 1…\(maxDefinitionWords)")
    }
    return problems
  }
}
