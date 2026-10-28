package import Foundation
internal import HelpKit
package import RenderKit
internal import SwiftUI

/// The « ? » of a Settings section (card 0114): its HelpKit card, the first line as the summary.
package enum SettingHelp {
  /// Settings › Storage (card 0114).
  package static let storage = "storage"
  /// Settings › Astro folder (card 0148).
  package static let astroFolder = "astro-folder"
  /// The settings with a card, by HelpKit id.
  package static let ids = [astroFolder, storage]

  /// The card of setting `id` in the language of `locale`, or `nil` (the gate keeps it present).
  package static func card(_ id: String, locale: Locale) -> String? {
    AppGlossary.help.settingCard(id, locale: AppLocale.language(of: locale))
  }

  /// The « ? » of setting `id`: the first line on hover, the whole card on click.
  package static func help(_ id: String, locale: Locale) -> KeyedHelp? {
    guard let text = card(id, locale: locale), let first = HelpMarkdown.parse(text).first else {
      return nil
    }
    let summary = first.runs.map(\.text).joined()
    return KeyedHelp(
      HelpContent(summary: .app("\(summary)")) { HelpText(text) }, key: .help("setting." + id))
  }
}
