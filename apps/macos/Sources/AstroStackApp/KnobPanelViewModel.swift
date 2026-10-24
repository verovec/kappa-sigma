package import Foundation
internal import Observation
package import ProcessKit
package import StackKit

/// The Stacking panel's knobs (card 0070), rendered from `KnobSchema`: the preset of `mode`
/// plus the user's edits, which are exactly the patch the run applies and records.
///
/// Simple knobs show first, advanced ones behind the disclosure, none is ever hidden (R2). An
/// edit equal to the preset's value is no edit, so an untouched run stays byte-identical.
@Observable
package final class KnobPanelViewModel {
  /// One knob as the panel shows it.
  package struct Row: Identifiable, Equatable, Sendable {
    /// The knob's wire id.
    package let id: String
    /// Where the panel shows it.
    package let level: Knob.Level
    /// Number, flag or choice, with its bounds or options.
    package let kind: Knob.Kind
    /// Per lane or for the whole run (card 0121).
    package let scope: Knob.Scope
    /// The value the run applies.
    package let value: KnobValue
    /// The preset's value; on a lane's row, the global value the lane falls back to.
    package let defaultValue: KnobValue
    package var isDefault: Bool { value == defaultValue }
    /// The glossary term of the knob (`knob.<id>`), its label and its one-line why.
    package var termID: String { Knob.termID(id) }
  }

  /// The preset the defaults come from.
  ///
  /// Switching keeps every edit: one equal to the new preset's value is simply no change there,
  /// and is back when the preset is switched back.
  package var mode: PreprocessRequest.Mode
  /// The advanced knobs are shown.
  package var showsAdvanced = false
  /// The profile the stack's source kept (0060), whose « why » joins the help of each knob it
  /// sets; nothing is applied from it here.
  package var profile: Profile?
  /// Recorded edits the schema no longer accepts (a renamed knob, narrower bounds): dropped and
  /// shown, never applied silently (R2).
  package private(set) var ignored: [String]
  /// What follows the stack of a split run (card 0121): one flow unless the user picks per channel.
  package var processing = StackProcessing.single
  /// The user's values by knob id, each accepted by the schema when it was set.
  private var edits: [String: KnobValue]
  /// The user's lane values (card 0121) by lane kind, then knob id: lane-scoped knobs only, each
  /// accepted by the schema when it was set.
  var laneEdits: [FilterSet: [String: KnobValue]] = [:]

  /// A panel over the preset of `mode` with `patch` already applied (a stack's recorded one); an
  /// entry the schema refuses lands in `ignored`, after the record's own `ignored` values.
  package init(
    mode: PreprocessRequest.Mode, patch: KnobPatch = KnobPatch(), ignored: [String] = []
  ) {
    self.mode = mode
    var accepted: [String: KnobValue] = [:]
    var refused: [String] = []
    for (id, value) in patch.values {
      if KnobSchema.knob(id)?.accepts(value) == true {
        accepted[id] = value
      } else {
        refused.append(id)
      }
    }
    edits = accepted
    self.ignored = ignored + refused.sorted()
  }

  /// The help of knob `id` in `locale` (`HelpMarkdown`): its glossary definition and, when
  /// `profile` sets the knob, a second paragraph naming the profile, the value it sets and its
  /// why when it has one — the why belongs to that value, which may not be the one on screen
  /// (R2, card 0086).
  package func help(for id: String, locale: Locale) -> String {
    var definition = AppGlossary.term(Knob.termID(id), locale: locale, in: AppGlossary.knobs)
      .definition
    // A run-wide knob says why every lane shares it (card 0121), in the same paragraph.
    if case .run(let reason) = KnobSchema.knob(id)?.scope {
      definition += " " + String(localized: Self.sharedWords(reason, locale: locale))
    }
    guard let profile, let set = profile.preprocessing.knobs[id] else { return definition }
    let language = AppLocale.language(of: locale)
    let line = Self.profileLine(
      profile.title.text(language: language), Self.words(for: set, id: id, locale: locale),
      profile.preprocessing.why[id]?.text(language: language), locale: locale)
    return [definition, line].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
  }

  /// Why a run-wide knob holds one value for every lane: they land on one canvas.
  package nonisolated static func sharedWords(_ reason: Knob.Shared, locale: Locale)
    -> LocalizedStringResource
  {
    switch reason {
    case .registration:
      .app(
        "Shared by every lane: every lane is registered onto one reference, one canvas.",
        locale: locale)
    case .framing:
      .app("Shared by every lane: the crops cut every lane to the same field.", locale: locale)
    case .nights:
      .app(
        "Shared by every lane: the nights are matched on one scale and one seam for every lane.",
        locale: locale)
    case .breakpoints:
      .app(
        "Shared by every lane: the run pauses every lane alike, as the Tri stage sets it.",
        locale: locale)
    case .combine:
      .app(
        "Shared by every lane: the combine and its sky model read every lane together.",
        locale: locale)
    }
  }

  /// « Profile <profile>, <value>: <why> » with the locale's punctuation (French spaces its
  /// colon); without a why, « Profile <profile>, <value> »; without a value, « Profile
  /// <profile>: <why> »; nothing to say, nil.
  package nonisolated static func profileLine(
    _ profile: String, _ value: String?, _ why: String?, locale: Locale
  ) -> String? {
    // Keys with a word of their own: a bare "%@: %@" would be every "a: b" interpolation's key.
    switch (value, why) {
    case (let value?, let why?):
      String(localized: .app("Profile \(profile), \(value): \(why)", locale: locale))
    case (let value?, nil):
      String(localized: .app("Profile \(profile), \(value)", locale: locale))
    case (nil, let why?):
      String(localized: .app("Profile \(profile): \(why)", locale: locale))
    case (nil, nil):
      nil
    }
  }

  /// A profile's value of knob `id` as the panel shows it: the user's number, the choice's
  /// glossary label, « On » / « Off »; nil for a curve or a text (no knob is one).
  package nonisolated static func words(for value: ParamValue, id: String, locale: Locale)
    -> String?
  {
    switch value {
    case .number(let number): AstroFormat(locale: locale).parameter(number)
    case .flag(let flag):
      String(localized: flag ? .app("On", locale: locale) : .app("Off", locale: locale))
    case .choice(let option):
      AppGlossary.label(Knob.termID(id, option: option), locale: locale, in: AppGlossary.knobs)
    case .points, .text: nil
    }
  }

  /// What differs from the preset of `mode`: the patch the run applies and records.
  package var patch: KnobPatch { patch(for: mode) }

  /// The edits on the preset of `mode` (a run may use another preset than the panel's).
  package func patch(for mode: PreprocessRequest.Mode) -> KnobPatch {
    KnobSchema.patch(from: settings(for: mode), mode: mode)
  }

  /// Every knob, in schema order.
  package var rows: [Row] {
    let preset = PreprocessSettings.preset(mode)
    let applied = settings
    return KnobSchema.knobs.map { knob in
      Row(
        id: knob.id, level: knob.level, kind: knob.kind, scope: knob.scope,
        value: knob.value(in: applied),
        defaultValue: knob.value(in: preset))
    }
  }

  /// The knobs always shown.
  package var simpleRows: [Row] { rows.filter { $0.level == .simple } }

  /// The knobs behind the disclosure (`showsAdvanced`), never hidden for good (R2).
  package var advancedRows: [Row] { rows.filter { $0.level == .advanced } }

  /// Knobs moved from the preset.
  package var changedCount: Int { patch.values.count }

  /// The settings the run applies: the preset of `mode` with the edits.
  package var settings: PreprocessSettings { settings(for: mode) }

  /// The preset of `mode` with the edits, each applied on its own: every edit was accepted by the
  /// schema on entry, and one that could fail never takes the others with it.
  package func settings(for mode: PreprocessRequest.Mode) -> PreprocessSettings {
    Self.applying(edits, to: .preset(mode))
  }

  /// `settings` with `values` applied each on its own, in id order: every value was accepted on
  /// entry, and one that could fail never takes the others with it.
  nonisolated static func applying(_ values: [String: KnobValue], to settings: PreprocessSettings)
    -> PreprocessSettings
  {
    var settings = settings
    for (id, value) in values.sorted(by: { $0.key < $1.key }) {
      settings = (try? KnobSchema.apply(KnobPatch(values: [id: value]), to: settings)) ?? settings
    }
    return settings
  }

  /// Sets knob `id` to `value`; a value the schema refuses is ignored (the field shows the
  /// accepted value back).
  package func set(_ id: String, to value: KnobValue) {
    guard KnobSchema.knob(id)?.accepts(value) == true else { return }
    edits[id] = value
  }

  /// The panel as a recorded run left it (the latest stack, a paused run's Continue, card 0097):
  /// its preset, its edits, its lane values and its processing replace the panel's, so a frozen
  /// panel shows what the run applies (R2); what the schema refuses lands in `ignored`.
  package func load(_ record: StackRecord) {
    let recorded = Self(mode: record.mode, patch: record.knobs, ignored: record.ignoredEntries)
    mode = record.mode
    edits = recorded.edits
    processing = record.processing
    var refused: [String] = []
    laneEdits = [:]
    for (lane, patch) in record.laneKnobs {
      let (accepted, refusedIDs) = KnobSchema.laneAccepted(patch)
      if !accepted.values.isEmpty { laneEdits[lane] = accepted.values }
      refused += refusedIDs.map { StackRecord.laneEntry(lane.codingKey.stringValue, knob: $0) }
    }
    ignored = recorded.ignored + refused.sorted()
  }

  /// The record the ignored values came from was replaced by a run's clean one.
  package func clearIgnored() {
    ignored = []
  }

  /// Knob `id` back to the preset.
  package func reset(_ id: String) {
    edits[id] = nil
  }

  /// Every knob back to the preset, every lane back to the global values.
  package func resetAll() {
    edits = [:]
    laneEdits = [:]
    processing = .single
    ignored = []
  }

  /// The glossary terms the panel words: every knob and every choice of it.
  package nonisolated static var termIDs: [String] {
    KnobSchema.knobs.flatMap { knob -> [String] in
      guard case .choice(let options) = knob.kind else { return [Knob.termID(knob.id)] }
      return [Knob.termID(knob.id)] + options.map { Knob.termID(knob.id, option: $0) }
    }
  }
}
