internal import Observation
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
  /// Recorded edits the schema no longer accepts (a renamed knob, narrower bounds): dropped and
  /// shown, never applied silently (R2).
  package let ignored: [String]
  /// The user's values by knob id, each accepted by the schema when it was set.
  private var edits: [String: KnobValue]

  /// A panel over the preset of `mode` with `patch` already applied (a stack's recorded one); an
  /// entry the schema refuses lands in `ignored`.
  package init(mode: PreprocessRequest.Mode, patch: KnobPatch = KnobPatch()) {
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
    ignored = refused.sorted()
  }

  /// What differs from the preset of `mode`: the patch the run applies and records.
  package var patch: KnobPatch { KnobSchema.patch(from: settings, mode: mode) }

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

  /// The simple knobs, then the advanced ones when the disclosure is open.
  package var visibleRows: [Row] {
    rows.filter { showsAdvanced || $0.level == .simple }
  }

  /// Knobs moved from the preset.
  package var changedCount: Int { patch.values.count }

  /// The settings the run applies: the preset of `mode` with the edits.
  package var settings: PreprocessSettings {
    // Every edit was accepted by the schema on entry, so applying it cannot fail.
    (try? KnobSchema.apply(KnobPatch(values: edits), to: .preset(mode))) ?? .preset(mode)
  }

  /// Sets knob `id` to `value`; a value the schema refuses is ignored (the field shows the
  /// accepted value back).
  package func set(_ id: String, to value: KnobValue) {
    guard KnobSchema.knob(id)?.accepts(value) == true else { return }
    edits[id] = value
  }

  /// Knob `id` back to the preset.
  package func reset(_ id: String) {
    edits[id] = nil
  }

  /// Every knob back to the preset.
  package func resetAll() {
    edits = [:]
  }

  /// The glossary terms the panel words: every knob and every choice of it.
  package nonisolated static var termIDs: [String] {
    KnobSchema.knobs.flatMap { knob -> [String] in
      guard case .choice(let options) = knob.kind else { return [Knob.termID(knob.id)] }
      return [Knob.termID(knob.id)] + options.map { Knob.termID(knob.id, option: $0) }
    }
  }
}
