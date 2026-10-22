package import Foundation
internal import HelpKit
package import RenderKit
internal import SwiftUI

/// A journey stage's help (card 0086): its card from HelpKit, read once per stage and language,
/// the first line as the summary.
package enum StageHelp {
  /// A stage card with its first paragraph as plain text.
  private struct Card {
    let text: String
    let summary: String
  }

  /// Every stage card by stage, then language, parsed once: a body never reads the disk nor
  /// the Markdown.
  nonisolated private static let cards: [JourneyStage: [String: Card]] = {
    var cards: [JourneyStage: [String: Card]] = [:]
    for stage in JourneyStage.allCases {
      for language in HelpIndex.locales {
        guard let text = AppGlossary.help.stageCard(stage.rawValue, locale: language),
          let first = HelpMarkdown.parse(text).first
        else { continue }
        cards[stage, default: [:]][language] = Card(
          text: text, summary: first.runs.map(\.text).joined())
      }
    }
    return cards
  }()

  private static func card(_ stage: JourneyStage, in locale: Locale) -> Card? {
    cards[stage]?[AppLocale.language(of: locale)]
  }

  /// The card of `stage` in the language of `locale`, or `nil` (the gate keeps it present).
  package static func card(_ stage: JourneyStage, locale: Locale) -> String? {
    card(stage, in: locale)?.text
  }

  /// The card's first paragraph as plain text: the tooltip of the stage's « ? » and of its
  /// sidebar row.
  package static func summary(_ stage: JourneyStage, locale: Locale) -> String? {
    card(stage, in: locale)?.summary
  }

  /// The « ? » of `stage`: the summary on hover, the whole card on click, under the stage's key.
  package static func help(_ stage: JourneyStage, locale: Locale) -> KeyedHelp? {
    guard let card = card(stage, in: locale) else { return nil }
    return KeyedHelp(
      HelpContent(summary: .app("\(card.summary)")) { HelpText(card.text) }, key: key(stage))
  }

  /// The identifier of the stage's « ? ».
  package static func key(_ stage: JourneyStage) -> AccessibilityID {
    .help("stage." + stage.rawValue)
  }
}
