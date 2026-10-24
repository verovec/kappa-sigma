package import Foundation
internal import HelpKit
package import RenderKit
package import StackKit
internal import SwiftUI

/// The Objects section's help (card 0130): its card (`stage/objects.md`, gated like a stage's)
/// and the sentence of a catalogue that could not be read.
package enum ObjectsHelp {
  /// The help card's id under HelpKit's `stage/`.
  package static let cardID = "objects"

  /// The « ? » of the Objects section: the card's first paragraph on hover, the card on click.
  package static func help(locale: Locale) -> KeyedHelp? {
    let language = AppLocale.language(of: locale)
    guard let text = AppGlossary.help.stageCard(cardID, locale: language),
      let first = HelpMarkdown.parse(text).first
    else { return nil }
    let summary = first.runs.map(\.text).joined()
    return KeyedHelp(
      HelpContent(summary: .app("\(summary)")) { HelpText(text) }, key: .help("section.objects"))
  }

  /// Why the catalogue is not there, in the user's words (the missing Siril has its card).
  package static func reason(_ error: SkyCatalogueError) -> LocalizedStringResource {
    switch error {
    case .sirilMissing: .app("Siril is not installed: its object lists come with it.")
    case .catalogueMissing(let folder): .app("Siril’s object lists are missing from \(folder).")
    case .noObjects(let folder): .app("Siril’s object lists in \(folder) hold no object.")
    case .unreadable(let file, let reason): .app("Siril’s list \(file) cannot be read: \(reason)")
    case .missingColumns(let file): .app("Siril’s list \(file) has no name, ra, dec columns.")
    }
  }
}
