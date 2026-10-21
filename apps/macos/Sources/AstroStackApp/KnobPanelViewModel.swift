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
    package let id: String
    package let level: Knob.Level
    package let kind: Knob.Kind
    /// The value the run applies.
    package let value: KnobValue
    /// The preset's value.
    package let defaultValue: KnobValue
    package var isDefault: Bool { value == defaultValue }
    /// The glossary term of the knob (`knob.<id>`), its label and its one-line why.
    package var termID: String { Knob.termID(id) }
  }

  /// The preset the defaults come from; switching keeps the edits that still differ.
  package var mode: PreprocessRequest.Mode {
    // The user's edits only, onto the new preset: one now equal to its default is no edit.
    didSet { patch = KnobSchema.patch(from: settings, mode: mode) }
  }
  /// What the user changed from the preset.
  package private(set) var patch: KnobPatch
  /// The advanced knobs are shown.
  package var showsAdvanced = false

  /// A panel over the preset of `mode` with `patch` already applied (a stack's recorded one).
  package init(mode: PreprocessRequest.Mode, patch: KnobPatch = KnobPatch()) {
    self.mode = mode
    self.patch = patch
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

  /// The simple knobs, then the advanced ones when the disclosure is open.
  package var visibleRows: [Row] {
    rows.filter { showsAdvanced || $0.level == .simple }
  }

  /// Knobs moved from the preset.
  package var changedCount: Int { patch.values.count }

  /// The settings the run applies: the preset with the edits.
  package var settings: PreprocessSettings { settings(of: mode) }

  /// Sets knob `id` to `value`; a value the schema refuses is ignored (the field shows the
  /// accepted value back).
  package func set(_ id: String, to value: KnobValue) {
    guard let knob = KnobSchema.knob(id), knob.accepts(value) else { return }
    var values = patch.values
    values[id] = value
    if let applied = try? KnobSchema.apply(KnobPatch(values: values), to: .preset(mode)) {
      patch = KnobSchema.patch(from: applied, mode: mode)
    }
  }

  /// Knob `id` back to the preset.
  package func reset(_ id: String) {
    patch.values[id] = nil
  }

  /// Every knob back to the preset.
  package func resetAll() {
    patch = KnobPatch()
  }

  /// The glossary terms the panel words: every knob and every choice of it.
  package nonisolated static var termIDs: [String] {
    KnobSchema.knobs.flatMap { knob -> [String] in
      guard case .choice(let options) = knob.kind else { return [Knob.termID(knob.id)] }
      return [Knob.termID(knob.id)] + options.map { Knob.termID(knob.id, option: $0) }
    }
  }

  private func settings(of mode: PreprocessRequest.Mode) -> PreprocessSettings {
    // The patch only ever holds values the schema accepted.
    (try? KnobSchema.apply(patch, to: .preset(mode))) ?? .preset(mode)
  }
}
