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

  private let table: LocalizedTable<Term>

  /// The glossaries `<root>/<locale>/<file>`, one per `HelpIndex.locales`; a missing or malformed
  /// locale is an empty glossary that the gate reports.
  ///
  /// `glossary.json` holds the astronomy terms; `knobs.json` the preprocessing knobs and their
  /// choices (card 0070), so each vocabulary keeps its own gate.
  package init(root: URL, file: String = "glossary.json") {
    table = LocalizedTable(root: root, file: file)
  }

  /// HelpKit's glossary `file` in `bundle` (the packaged app passes its resolved resource bundle).
  package init(bundle: Bundle, file: String = "glossary.json") {
    self.init(
      root: bundle.resourceURL?.appendingPathComponent("Help") ?? bundle.bundleURL, file: file)
  }

  /// HelpKit's glossary as SwiftPM builds it (tests, `swift run`).
  package static var bundled: Self { Self(bundle: .module) }

  /// The term `id` in `locale` (`fr`, `en`), or `nil`.
  package func term(_ id: String, locale: String) -> Term? {
    table.entry(id, locale: locale)
  }

  /// One sentence per gate failure: an unreadable locale, an id missing from a locale, an empty
  /// label, or a definition longer than a line.
  package func problems(ids: [String]) -> [String] {
    table.problems(ids: ids, kind: "term", check: Self.problems(of:))
  }

  /// The ids of the `locale` file that `ids` does not name: words no catalog uses any more.
  package func stale(ids: [String], locale: String) -> [String] {
    table.stale(ids: ids, locale: locale)
  }

  private static func problems(of term: Term) -> [String] {
    var problems: [String] = []
    if term.label.trimmingCharacters(in: .whitespaces).isEmpty { problems.append("empty label") }
    return problems + definitionProblems(term.definition)
  }

  /// What makes `definition` more than a line: empty, over `maxDefinitionWords`, or a line
  /// break (shared with `ParamDocs`).
  package static func definitionProblems(_ definition: String) -> [String] {
    let words = definition.split(whereSeparator: \.isWhitespace).count
    guard words == 0 || words > maxDefinitionWords || definition.contains("\n") else { return [] }
    return ["definition of \(words) words, one line of 1…\(maxDefinitionWords)"]
  }
}
