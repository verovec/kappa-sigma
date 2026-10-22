internal import HelpKit
internal import RenderKit
internal import StackKit
internal import SwiftUI

/// One knob of the Stacking panel, worded by the knobs glossary: a number in a `ParameterRow`, a
/// flag in a toggle, a choice in a menu; a moved value has its reset at hand, and every kind has
/// its « ? » (the definition on hover, the definition and the profile's why on click — 0086).
struct KnobRow: View {
  let row: KnobPanelViewModel.Row
  let model: KnobPanelViewModel
  /// The value cannot move (a run is going); the « ? » still opens.
  var frozen = false
  @Environment(\.locale) private var locale

  var body: some View {
    let term = AppGlossary.term(row.termID, locale: locale, in: AppGlossary.knobs)
    switch row.kind {
    case .number(let bounds, let integer):
      ParameterRow(
        .app("\(term.label)"), parameter: number(bounds, integer: integer),
        help: help(term), key: row.id, frozen: frozen,
        format: { AstroFormat(locale: locale).parameter($0) },
        parse: { AstroFormat(locale: locale).parameter(parsing: $0) })
    case .flag:
      HStack {
        Toggle(isOn: flag) { Text(verbatim: term.label) }
          .accessible(control, verbatim: term.label)
          .disabled(frozen)
        helpButton(term)
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
        .accessible(control, verbatim: term.label)
        .disabled(frozen)
        helpButton(term)
        reset
      }
    }
  }

  /// The knob's help: its definition, and the kept profile's why when it sets this knob.
  private func help(_ term: Glossary.Term) -> HelpContent {
    HelpContent(summary: .app("\(term.definition)")) {
      HelpText(model.help(for: row.id, locale: locale))
    }
  }

  /// Back to the preset, shown once the value moved.
  @ViewBuilder private var reset: some View {
    if !row.isDefault {
      Button {
        model.reset(row.id)
      } label: {
        Image(systemName: "arrow.uturn.backward")
      }
      .buttonStyle(.borderless)
      .disabled(frozen)
      .help(Text(.app("Back to the preset")))
      .accessible(.parameter(row.id, .reset), label: .app("Back to the preset"))
    }
  }

  /// The « ? » of a flag or choice row (a number row's sits in its `ParameterRow`).
  private func helpButton(_ term: Glossary.Term) -> some View {
    KeyedHelp(help(term), key: .parameter(row.id, .help), label: .whyThisValue).button
  }

  /// The identifier of a flag or choice knob: its term id under the stacking stage.
  private var control: AccessibilityID { .stackingKnob(row.termID) }

  /// A whole-number knob rounds what the slider sends: the schema refuses a fraction.
  private func number(_ bounds: ClosedRange<Double>, integer: Bool) -> Binding<ParameterValue> {
    Binding(
      get: {
        ParameterValue(default: row.defaultValue.number, range: bounds, value: row.value.number)
      },
      set: { parameter in
        // The row's own reset lands exactly on the default: clear the edit, never pin it.
        if parameter.isDefault {
          model.reset(row.id)
        } else {
          model.set(row.id, to: .number(integer ? parameter.value.rounded() : parameter.value))
        }
      })
  }

  private var flag: Binding<Bool> {
    Binding(get: { row.value == .flag(true) }, set: { model.set(row.id, to: .flag($0)) })
  }

  private var choice: Binding<String> {
    Binding(get: { row.value.description }, set: { model.set(row.id, to: .choice($0)) })
  }
}

extension KnobValue {
  /// The number of a numeric knob (0 for another kind: never shown as a number).
  fileprivate var number: Double {
    if case .number(let value) = self { return value }
    return 0
  }
}
