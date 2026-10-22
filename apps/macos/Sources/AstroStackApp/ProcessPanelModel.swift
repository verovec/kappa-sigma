package import Foundation
internal import HelpKit
internal import Observation
package import ProcessKit
package import RenderKit

/// The values the process panel edits (card 0087): one process's `ParamSet`, the advanced
/// disclosure, the process's suggestions (applied on click only, R2) and its card.
@Observable
package final class ProcessPanelModel {
  /// The process.
  @ObservationIgnored package let type: any ImageProcess.Type
  /// The values the preview and Apply use.
  package private(set) var params: ParamSet {
    didSet { measureClipping() }
  }
  /// The advanced parameters are shown.
  package var showsAdvanced = false
  /// What the process proposes from the statistics of the head (refreshed when it moves);
  /// nothing is set until one is taken.
  package var suggestions: [Suggestion]
  /// The head's sample (card 0089): the input histogram the handles sit on, the clipping
  /// readouts; `nil` until measured.
  package var sample: HeadSample? {
    didSet { measureClipping() }
  }
  /// The head's statistics (the stretch's handles read them).
  package var headStats = LayerStats(channels: [])
  /// What the levels send to black and white on the head's sample, per channel (measured once
  /// per change of the values or the sample, shown, never applied); none for another process.
  package internal(set) var clipping: [HeadSample.Clipping] = []
  /// Called after every accepted change (the live preview).
  @ObservationIgnored package var onChange: () -> Void = {}

  /// A panel of `type` starting at `params`, with `suggestions`.
  package init(type: any ImageProcess.Type, params: ParamSet, suggestions: [Suggestion] = []) {
    self.type = type
    self.params = params
    self.suggestions = suggestions
  }

  /// The parameters the panel shows: simple ones, advanced ones once disclosed or promoted by
  /// the current values (the levels' per-channel rows once unlinked).
  package var visibleSpecs: [ParamSpec] {
    // A mono head has no per-channel values to promote.
    let colour = (sample?.planes.count ?? headStats.channels.count) == 3
    return type.schema.visible(
      disclosed: showsAdvanced, promoted: colour ? type.promoted(params) : [])
  }

  /// The arrow step of `id`, when the process gives one.
  package func step(for id: String) -> ParameterStep? {
    type.steps[id].map(ParameterStep.init)
  }

  /// The key the input histogram is identified by.
  package var histogramKey: String { "studio." + type.id }

  /// The key the « take together » buttons are identified by.
  package var togetherKey: String { type.id + ".together" }

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

  /// The reasons several suggestions share (one click takes them all), in order.
  package var groupedReasons: [String] {
    var seen: [String] = []
    for suggestion in suggestions where !seen.contains(suggestion.reason) {
      if suggestions.filter({ $0.reason == suggestion.reason }).count > 1 {
        seen.append(suggestion.reason)
      }
    }
    return seen
  }

  /// Replaces the values (a handle drag) and previews them.
  func replace(_ params: ParamSet) {
    guard params != self.params else { return }
    self.params = params
    onChange()
  }

  /// Takes every suggestion of `reason` (the user's click on the group), in their order.
  package func take(reason: String) {
    var params = params
    for suggestion in suggestions where suggestion.reason == reason {
      try? params.set(suggestion.paramID, suggestion.value)
    }
    replace(params)
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
