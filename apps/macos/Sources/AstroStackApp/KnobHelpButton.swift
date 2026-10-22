package import Foundation
internal import HelpKit
package import RenderKit
internal import StackKit
package import SwiftUI

/// The « ? » of a preprocessing knob wherever it is shown (card 0086): the glossary definition
/// on hover, the definition and the kept profile's line on click, keyed `parameter.<id>.help`.
package struct KnobHelpButton: View {
  let id: String
  let model: KnobPanelViewModel
  @Environment(\.locale) private var locale

  /// The « ? » of knob `id`, worded from `model`.
  package init(id: String, model: KnobPanelViewModel) {
    self.id = id
    self.model = model
  }

  package var body: some View {
    KeyedHelp(content, key: .parameter(id, .help), label: .whyThisValue).button
  }

  /// The knob's help content, for a `ParameterRow` too.
  package static func content(_ id: String, model: KnobPanelViewModel, locale: Locale)
    -> HelpContent
  {
    let term = AppGlossary.term(Knob.termID(id), locale: locale, in: AppGlossary.knobs)
    return HelpContent(summary: .app("\(term.definition)")) {
      HelpText(model.help(for: id, locale: locale))
    }
  }

  private var content: HelpContent { Self.content(id, model: model, locale: locale) }
}
