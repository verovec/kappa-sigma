package import Foundation

/// The help cards on disk, in every locale the app ships.
///
/// Cards are `<root>/<locale>/process/<process id>.md`. The coverage gate (`coverageProblems`) keeps every registered process documented and
/// every card short; `HelpMarkdown` renders them (card 0061). The first-stack guide is
/// `<root>/<locale>/guide/first-stack.md`, one step per line.
package struct HelpIndex: Sendable {
  /// The locales every card must exist in.
  package static let locales = ["fr", "en"]
  /// A card's limits (design §6: a card is read at a glance).
  package static let maxLines = 5
  /// Words, over the whole card.
  package static let maxWords = 90
  /// Words in one guide step: it is read beside the control it points at.
  package static let maxStepWords = 40

  /// The folder holding the locale folders.
  package let root: URL

  /// The cards under `root`.
  package init(root: URL) {
    self.root = root
  }

  /// HelpKit's own cards in `bundle` (the packaged app passes its resolved resource bundle).
  package init(bundle: Bundle) {
    root = bundle.resourceURL?.appendingPathComponent("Help") ?? bundle.bundleURL
  }

  /// HelpKit's cards as SwiftPM builds them (tests, `swift run`).
  package static var bundled: Self { Self(bundle: .module) }

  /// The card of process `id` in `locale`, or `nil`.
  package func card(process id: String, locale: String) -> String? {
    let url = root.appendingPathComponent(locale).appendingPathComponent("process")
      .appendingPathComponent(id + ".md")
    return try? String(contentsOf: url, encoding: .utf8)
  }

  /// One sentence per gate failure for `processIDs`: a missing locale, or a card too long.
  package func coverageProblems(processIDs: [String]) -> [String] {
    processIDs.flatMap { id in
      Self.locales.flatMap { locale -> [String] in
        guard let text = card(process: id, locale: locale) else {
          return ["\(id): no \(locale) card"]
        }
        return Self.cardProblems(text).map { "\(id) (\(locale)): \($0)" }
      }
    }
  }

  /// The first-stack guide's steps in `locale`, one per non-blank line; empty without the file.
  package func guide(locale: String) -> [String] {
    let url = root.appendingPathComponent(locale).appendingPathComponent("guide")
      .appendingPathComponent("first-stack.md")
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
    return text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
  }

  /// One sentence per guide failure: a missing locale, a count other than `steps`, a long step.
  package func guideProblems(steps: Int) -> [String] {
    Self.locales.flatMap { locale -> [String] in
      let text = guide(locale: locale)
      guard !text.isEmpty else { return ["guide: no \(locale) text"] }
      var problems: [String] = []
      if text.count != steps {
        problems.append("guide (\(locale)): \(text.count) steps, not \(steps)")
      }
      for (index, step) in text.enumerated() {
        let words = step.split(whereSeparator: { $0.isWhitespace }).count
        if words > Self.maxStepWords {
          problems.append(
            "guide (\(locale)) step \(index + 1): \(words) words > \(Self.maxStepWords)")
        }
      }
      return problems
    }
  }

  /// What makes `text` too long for a card.
  package static func cardProblems(_ text: String) -> [String] {
    var problems: [String] = []
    let lines = text.split(separator: "\n", omittingEmptySubsequences: true).count
    if lines > maxLines { problems.append("\(lines) lines > \(maxLines)") }
    let words = text.split(whereSeparator: { $0.isWhitespace }).count
    if words > maxWords { problems.append("\(words) words > \(maxWords)") }
    return problems
  }
}
