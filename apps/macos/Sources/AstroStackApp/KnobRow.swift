internal import HelpKit
internal import RenderKit
internal import StackKit
internal import SwiftUI

/// One knob of the Stacking panel, worded by the knobs glossary: a number in a `ParameterRow`, a
/// flag in a toggle, a choice in a menu; a moved value has its reset at hand, and every kind has
/// its « ? » (the definition on hover, the definition and the profile's why on click — 0086).
///
/// On a lane (card 0121) a lane knob edits that lane's value, badged « ≠ global » once it differs,
/// its reset back to the global value; a run-wide knob shows the global value, greyed, shared.
struct KnobRow: View {
  let row: KnobPanelViewModel.Row
  let model: KnobPanelViewModel
  /// The lane the row edits; nil: the global value.
  var lane: FilterSet?
  /// The value cannot move (a run is going); the « ? » still opens.
  var frozen = false
  @Environment(\.locale) private var locale

  /// A run-wide knob on a lane: every lane shares the global value.
  private var shared: Bool { lane != nil && row.scope != .lane }
  /// The value cannot move here: a run is going, or the knob is shared.
  private var locked: Bool { frozen || shared }

  var body: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingXS) {
      control
      if shared {
        Text(.app("Shared by every lane")).font(.caption).foregroundStyle(.secondary)
      } else if lane != nil && !row.isDefault {
        StatusBadge(.attention, .app("≠ global"))
      }
    }
  }

  @ViewBuilder private var control: some View {
    let term = AppGlossary.term(row.termID, locale: locale, in: AppGlossary.knobs)
    switch row.kind {
    case .number(let bounds, let integer):
      ParameterRow(
        .app("\(term.label)"), parameter: number(bounds, integer: integer),
        help: KnobHelpButton.content(row.id, model: model, locale: locale), key: row.id,
        frozen: locked,
        format: { AstroFormat(locale: locale).parameter($0) },
        parse: { AstroFormat(locale: locale).parameter(parsing: $0) })
    case .flag:
      HStack {
        Toggle(isOn: flag) { Text(verbatim: term.label) }
          .accessible(identifier, verbatim: term.label)
          .disabled(locked)
        KnobHelpButton(id: row.id, model: model)
        Spacer()
        reset
      }
    case .choice(let options):
      HStack {
        Picker(selection: choice) {
          ForEach(options, id: \.self) { option in
            Text(
              verbatim: AppGlossary.label(
                Knob.termID(row.id, option: option), locale: locale, in: AppGlossary.knobs)
            )
            .tag(option)
          }
        } label: {
          Text(verbatim: term.label)
        }
        .accessible(identifier, verbatim: term.label)
        .disabled(locked)
        KnobHelpButton(id: row.id, model: model)
        reset
      }
    }
  }

  /// Back to the preset — on a lane, to the global value — shown once the value moved.
  @ViewBuilder private var reset: some View {
    if !row.isDefault && !shared {
      let words: LocalizedStringResource =
        lane == nil ? .app("Back to the preset") : .app("Back to the global value")
      Button {
        clear()
      } label: {
        Image(systemName: "arrow.uturn.backward")
      }
      .buttonStyle(.borderless)
      .disabled(locked)
      .help(Text(words))
      .accessible(.parameter(row.id, .reset), label: words)
    }
  }

  /// The identifier of a flag or choice knob: its term id under the stacking stage.
  private var identifier: AccessibilityID { .stackingKnob(row.termID) }

  /// The edit of this row cleared: the lane's override, or the global edit.
  private func clear() {
    if let lane { model.reset(row.id, lane: lane) } else { model.reset(row.id) }
  }

  /// `value` written where the row edits: the lane, or the global values.
  private func write(_ value: KnobValue) {
    if let lane { model.set(row.id, to: value, lane: lane) } else { model.set(row.id, to: value) }
  }

  /// A whole-number knob rounds what the slider sends: the schema refuses a fraction.
  private func number(_ bounds: ClosedRange<Double>, integer: Bool) -> Binding<ParameterValue> {
    Binding(
      get: {
        ParameterValue(default: row.defaultValue.number, range: bounds, value: row.value.number)
      },
      set: { parameter in
        // The row's own reset lands exactly on the default: clear the edit, never pin it.
        if parameter.isDefault {
          clear()
        } else {
          write(.number(integer ? parameter.value.rounded() : parameter.value))
        }
      })
  }

  private var flag: Binding<Bool> {
    Binding(get: { row.value == .flag(true) }, set: { write(.flag($0)) })
  }

  private var choice: Binding<String> {
    Binding(get: { row.value.description }, set: { write(.choice($0)) })
  }
}

extension KnobValue {
  /// The number of a numeric knob (0 for another kind: never shown as a number).
  fileprivate var number: Double {
    if case .number(let value) = self { return value }
    return 0
  }
}
