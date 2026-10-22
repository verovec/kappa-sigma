internal import HelpKit
package import RenderKit
package import SwiftUI

/// A journey stage's help (card 0086): its card from HelpKit, read once per stage and language,
/// the first line as the summary.
package enum StageHelp {
  /// Every stage card, keyed `<stage>|<language>`: a body never reads the disk.
  nonisolated private static let cards: [String: String] = {
    var cards: [String: String] = [:]
    for stage in JourneyStage.allCases {
      for language in HelpIndex.locales {
        if let card = AppGlossary.help.stageCard(stage.rawValue, locale: language) {
          cards["\(stage.rawValue)|\(language)"] = card
        }
      }
    }
    return cards
  }()

  /// The card of `stage` in the language of `locale`, or `nil` (the gate keeps it present).
  package static func card(_ stage: JourneyStage, locale: Locale) -> String? {
    cards["\(stage.rawValue)|\(AppLocale.language(of: locale))"]
  }

  /// The card's first line: the tooltip of the stage's « ? » and of its sidebar row.
  package static func summary(_ stage: JourneyStage, locale: Locale) -> String? {
    card(stage, locale: locale).flatMap(Self.firstLine)
  }

  /// The « ? » of `stage`: the summary on hover, the whole card on click, under the stage's key.
  package static func help(_ stage: JourneyStage, locale: Locale) -> KeyedHelp? {
    guard let card = card(stage, locale: locale), let summary = firstLine(card) else { return nil }
    return KeyedHelp(
      HelpContent(summary: .app("\(summary)")) { HelpText(card) }, key: key(stage))
  }

  /// The identifier of the stage's « ? ».
  package static func key(_ stage: JourneyStage) -> AccessibilityID {
    .help("stage." + stage.rawValue)
  }

  private static func firstLine(_ card: String) -> String? {
    card.split(whereSeparator: \.isNewline).first.map(String.init)
  }
}
