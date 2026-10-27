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
    didSet {
      measureClipping()
      hidden = hiddenNow
    }
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
  /// Where the head points when it already carries a solution (plate solving, card 0130): shown
  /// read-only; nil without one or for another process.
  package var solved: PlateSolveStatus?
  /// The head's statistics (the stretch's handles read them).
  package var headStats = LayerStats(channels: [])
  /// What the levels send to black and white on the head's sample, per channel (measured once
  /// per change of the values or the sample, shown, never applied); none for another process.
  package internal(set) var clipping: [HeadSample.Clipping] = []
  /// Choice options that cannot run, by parameter then option, with the reason (an engine
  /// whose tool is missing, card 0092): shown greyed, never switched away from (R2).
  package var unavailableOptions: [String: [String: LocalizedStringResource]] = [:]
  /// The bundle layers the panel's process may read (card 0135).
  ///
  /// A line's rows show only while its layer is among them, or while the values still ask for
  /// it; `nil` until the workspace says (a panel built elsewhere hides nothing).
  package var layerIDs: Set<String>? {
    didSet { hidden = hiddenNow }
  }
  /// Why a row's value cannot run on this stack, by parameter id (card 0135).
  ///
  /// Shown under the row, never greying the process. Set by the workspace with the values.
  package var rowNotes: [String: RowNote] = [:]
  /// The head's size in full-resolution pixels (`nil` until the workspace sets it).
  ///
  /// Setting it sizes the sliders the process sizes from the image (`displayRanges`).
  @ObservationIgnored package var headSize: (width: Int, height: Int)? {
    didSet {
      let ranges = headSize.map { type.displayRanges(width: $0.width, height: $0.height) } ?? [:]
      // Only a change redraws the rows: a head moved without resizing leaves the sliders as is.
      if ranges != displayRanges { displayRanges = ranges }
    }
  }
  /// The slider ranges the process gives on the head, by id (`ImageProcess.displayRanges`).
  package private(set) var displayRanges: [String: ClosedRange<Double>] = [:]
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
      disclosed: showsAdvanced, promoted: colour ? type.promoted(params) : [], hidden: hidden)
  }

  /// The parameters hidden for the bundle (card 0135); none until the workspace sets the layers.
  ///
  /// Kept with the values and the layers, not computed per view evaluation.
  private var hidden: Set<String> = []
  private var hiddenNow: Set<String> {
    layerIDs.map { type.hiddenParameters(params, layerIDs: $0) } ?? []
  }

  /// Whether the « Advanced » disclosure opens onto anything: an advanced row that is not hidden.
  package var hasAdvanced: Bool {
    type.schema.specs.contains { $0.level == .advanced && !hidden.contains($0.id) }
  }

  /// The arrow step of `id`, when the process gives one.
  package func step(for id: String) -> ParameterStep? {
    type.steps[id].map(ParameterStep.init)
  }

  /// The slider range of `spec`: the process's display range on the head when it gives one, else
  /// the schema bounds (also when the head leaves the slider no travel, a 1-pixel side); widened
  /// to hold the value and the default, since a typed value is never clamped to the slider (R2).
  /// `nil` for a parameter without a slider.
  package func range(for spec: ParamSpec) -> ClosedRange<Double>? {
    guard case .number(let fallback, let bounds) = spec.kind else { return nil }
    guard let display = displayRanges[spec.id], display.upperBound > display.lowerBound else {
      return bounds
    }
    return display.widened(toHold: [params.number(spec.id), fallback]).clamped(to: bounds)
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

  /// The subject of the suggestions of `reason` (card 0130: the catalogue object), if any.
  package func subject(of reason: String) -> String? {
    suggestions.first { $0.reason == reason }?.subject
  }

  /// `reason` in the language of `locale` (ProcessKit's catalog holds every reason), with its
  /// `subject` when it has one: « From the catalogue (Sh2-132) ».
  package nonisolated static func words(reason: String, subject: String?, locale: Locale)
    -> String
  {
    let words = String(localized: ProcessKitResources.title(reason, locale: locale))
    guard let subject else { return words }
    return String(localized: .app("\(words) about \(subject)", locale: locale))
  }

  /// The solution the head carries, as the plate-solve panel words it: « Already solved: centre
  /// 22h18m51,8s +56°08′05″, 1,52″/px ».
  package nonisolated static func solvedWords(_ status: PlateSolveStatus, locale: Locale) -> String
  {
    let format = AstroFormat(locale: locale)
    let ra = format.rightAscension(degrees: status.raDeg)
    let dec = format.declination(degrees: status.decDeg)
    let scale = format.decimal(status.arcsecPerPixel, maxFractionDigits: 2)
    return String(
      localized: .app("Already solved: centre \(ra) \(dec), \(scale)″/px", locale: locale))
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
