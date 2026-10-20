package import Foundation

/// The help cards on disk: `<root>/<locale>/process/<process id>.md`, in every locale the app
/// ships. The coverage gate (`coverageProblems`) keeps every registered process documented and
/// every card short; the renderer comes with card 0061.
package struct HelpIndex: Sendable {
  /// The locales every card must exist in.
  package static let locales = ["fr", "en"]
  /// A card's limits (design §6: a card is read at a glance).
  package static let maxLines = 5
  /// Words, over the whole card.
  package static let maxWords = 90

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
        guard let text = card(process: id, locale: locale) else { return ["\(id): no \(locale) card"] }
        return Self.cardProblems(text).map { "\(id) (\(locale)): \($0)" }
      }
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
