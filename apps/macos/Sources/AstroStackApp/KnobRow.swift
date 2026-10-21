internal import RenderKit
internal import StackKit
internal import SwiftUI

/// One knob of the Stacking panel, worded by the knobs glossary: a number in a `ParameterRow`, a
/// flag in a toggle, a choice in a menu; a moved value has its reset at hand.
struct KnobRow: View {
  let row: KnobPanelViewModel.Row
  let model: KnobPanelViewModel
  @Environment(\.locale) private var locale

  var body: some View {
    let term = AppGlossary.term(row.termID, locale: locale, in: AppGlossary.knobs)
    switch row.kind {
    case .number(let bounds, let integer):
      ParameterRow(
        .app("\(term.label)"), parameter: number(bounds, integer: integer),
        why: .app("\(term.definition)"),
        format: { AstroFormat(locale: locale).parameter($0) },
        parse: { AstroFormat(locale: locale).parameter(parsing: $0) })
    case .flag:
      HStack {
        Toggle(isOn: flag) { Text(verbatim: term.label) }
        Spacer()
        reset
      }
      .help(term.definition)
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
        reset
      }
      .help(term.definition)
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
      .help(Text(.app("Back to the preset")))
    }
  }

  /// A whole-number knob rounds what the slider sends: the schema refuses a fraction.
  private func number(_ bounds: ClosedRange<Double>, integer: Bool) -> Binding<ParameterValue> {
    Binding(
      get: {
        ParameterValue(default: row.defaultValue.number, range: bounds, value: row.value.number)
      },
      set: { model.set(row.id, to: .number(integer ? $0.value.rounded() : $0.value)) })
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
