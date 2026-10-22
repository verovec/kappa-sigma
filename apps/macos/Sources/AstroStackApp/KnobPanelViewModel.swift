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
    /// The value the run applies.
    package let value: KnobValue
    /// The preset's value.
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
  /// The user's values by knob id, each accepted by the schema when it was set.
  private var edits: [String: KnobValue]

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
  /// `profile` sets the knob, a second paragraph naming the profile, the value it sets and why —
  /// the why belongs to that value, which may not be the one on screen (R2, card 0086).
  package func help(for id: String, locale: Locale) -> String {
    let definition = AppGlossary.term(Knob.termID(id), locale: locale, in: AppGlossary.knobs)
      .definition
    guard let profile, let why = profile.preprocessing.why[id] else { return definition }
    let language = AppLocale.language(of: locale)
    let value = profile.preprocessing.knobs[id].flatMap {
      Self.words(for: $0, id: id, locale: locale)
    }
    return definition + "\n"
      + Self.profileLine(
        profile.title.text(language: language), value, why.text(language: language),
        locale: locale)
  }

  /// « <profile>, <value>: <why> » with the locale's punctuation (French spaces its colon).
  package nonisolated static func profileLine(
    _ profile: String, _ value: String?, _ why: String, locale: Locale
  ) -> String {
    if let value {
      return String(localized: .app("\(profile), \(value): \(why)", locale: locale))
    }
    return String(localized: .app("\(profile): \(why)", locale: locale))
  }

  /// A profile's value of knob `id` as the panel shows it: the user's number, the choice's
  /// glossary label, « On » / « Off »; nil for a curve (no knob is one).
  package nonisolated static func words(for value: ParamValue, id: String, locale: Locale)
    -> String?
  {
    switch value {
    case .number(let number): AstroFormat(locale: locale).parameter(number)
    case .flag(let flag):
      String(localized: flag ? .app("On", locale: locale) : .app("Off", locale: locale))
    case .choice(let option):
      AppGlossary.label(Knob.termID(id, option: option), locale: locale, in: AppGlossary.knobs)
    case .points: nil
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
        id: knob.id, level: knob.level, kind: knob.kind, value: knob.value(in: applied),
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
    var settings = PreprocessSettings.preset(mode)
    for (id, value) in edits.sorted(by: { $0.key < $1.key }) {
      let edit = KnobPatch(values: [id: value])
      settings = (try? KnobSchema.apply(edit, to: settings)) ?? settings
    }
    return settings
  }

  /// Sets knob `id` to `value`; a value the schema refuses is ignored (the field shows the
  /// accepted value back).
  package func set(_ id: String, to value: KnobValue) {
    guard KnobSchema.knob(id)?.accepts(value) == true else { return }
    edits[id] = value
  }

  /// The record the ignored values came from was replaced by a run's clean one.
  package func clearIgnored() {
    ignored = []
  }

  /// Knob `id` back to the preset.
  package func reset(_ id: String) {
    edits[id] = nil
  }

  /// Every knob back to the preset.
  package func resetAll() {
    edits = [:]
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
