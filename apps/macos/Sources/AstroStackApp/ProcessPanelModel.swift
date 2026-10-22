package import Foundation
internal import HelpKit
internal import Observation
package import ProcessKit

/// The values the process panel edits (card 0087): one process's `ParamSet`, the advanced
/// disclosure, the process's suggestions (applied on click only, R2) and its card.
@Observable
package final class ProcessPanelModel {
  /// The process.
  @ObservationIgnored package let type: any ImageProcess.Type
  /// The values the preview and Apply use.
  package private(set) var params: ParamSet
  /// The advanced parameters are shown.
  package var showsAdvanced = false
  /// What the process proposes from the statistics of the head (refreshed when it moves);
  /// nothing is set until one is taken.
  package var suggestions: [Suggestion]
  /// Called after every accepted change (the live preview).
  @ObservationIgnored package var onChange: () -> Void = {}

  /// A panel of `type` starting at `params`, with `suggestions`.
  package init(type: any ImageProcess.Type, params: ParamSet, suggestions: [Suggestion] = []) {
    self.type = type
    self.params = params
    self.suggestions = suggestions
  }

  /// The parameters the panel shows: simple ones, advanced ones once disclosed.
  package var visibleSpecs: [ParamSpec] {
    type.schema.visible(disclosed: showsAdvanced)
  }

  /// The key a parameter's controls are identified by.
  package func key(_ spec: ParamSpec) -> String {
    "\(type.id).\(spec.id)"
  }

  /// Sets `id` to `value` as the schema accepts it (clamped); a refused value changes nothing.
  package func set(_ id: String, _ value: ParamValue) {
    guard (try? params.set(id, value)) != nil else { return }
    onChange()
  }

  /// Takes `suggestion`: its value becomes the parameter's (the user's click).
  package func take(_ suggestion: Suggestion) {
    set(suggestion.paramID, suggestion.value)
  }

  /// The process card in the language of `locale` (`HelpIndex.card`, 0061).
  package func card(locale: Locale) -> String? {
    AppGlossary.help.card(process: type.id, locale: AppLocale.language(of: locale))
  }

  /// The parameter's one-line definition (`params.json`, 0086).
  package func definition(_ spec: ParamSpec, locale: Locale) -> String? {
    AppGlossary.help.paramDoc(
      process: type.id, param: spec.id, locale: AppLocale.language(of: locale))
  }
}
