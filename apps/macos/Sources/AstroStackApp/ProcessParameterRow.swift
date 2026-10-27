internal import HelpKit
internal import ProcessKit
internal import RenderKit
internal import SwiftUI

/// One parameter of the process panel, by kind: a `ParameterRow` for a number, a toggle, a
/// menu, a curve; each with its « ? » (the `params.json` definition) and the suggestions that
/// name it.
struct ProcessParameterRow: View {
  let spec: ParamSpec
  let model: ProcessPanelModel
  @Environment(\.locale) private var locale

  var body: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingXS) {
      control
      // Why this value cannot run on the stack (card 0135): said, never enforced (R2).
      if let note = model.rowNotes[spec.id] {
        Text(
          verbatim: ProcessPanelModel.words(
            reason: note.reason, subject: note.subject, locale: locale)
        )
        .font(.caption)
        .foregroundStyle(DesignColor.textSecondary.color)
        .accessible(.parameter(key, .note), label: label)
      }
      ForEach(Array(suggestions.enumerated()), id: \.offset) { offset, suggestion in
        Button {
          model.take(suggestion)
        } label: {
          Text(.app("Suggested: \(words(suggestion.value)) — \(reason(suggestion))"))
            .font(.caption)
        }
        .buttonStyle(.link)
        .accessible(.suggestion(key, offset), label: .app("Suggested value"))
      }
    }
  }

  private var key: String { model.key(spec) }
  private var label: LocalizedStringResource {
    ProcessKitResources.title(spec.title, locale: locale)
  }
  private var suggestions: [Suggestion] {
    model.suggestions.filter { $0.paramID == spec.id }
  }

  @ViewBuilder private var control: some View {
    switch spec.kind {
    case .number(let fallback, let bounds):
      ParameterRow(
        label, parameter: number(fallback, bounds), help: help, key: key,
        step: model.step(for: spec.id),
        format: { AstroFormat(locale: locale).parameter($0) },
        parse: { AstroFormat(locale: locale).parameter(parsing: $0) })
    case .flag:
      HStack {
        Toggle(isOn: flag) { Text(label) }
          .accessible(.parameter(key, .toggle), label: label)
        helpButton
      }
    case .choice(_, let options):
      picker(options)
    case .layer(_, let allowsNone, let allowsProduct):
      // The bundle names the options (card 0138); the value chosen stays listed.
      picker(
        model.layerOptions(for: spec.id, allowsNone: allowsNone, allowsProduct: allowsProduct))
    case .text:
      HStack {
        TextField(text: text) { Text(label) }
          .accessible(.parameter(key, .text), label: label)
        helpButton
      }
    case .points(_, let maxCount):
      CurveEditor(
        label, points: points(maxCount), key: key,
        curve: { points in
          let spline = MonotoneSpline(points.map { CurvePoint($0.x, $0.y) })
          return { spline($0) }
        })
    }
  }

  private var help: HelpContent? {
    guard let definition = model.definition(spec, locale: locale) else { return nil }
    return HelpContent(summary: .app("\(definition)")) { HelpText(definition) }
  }

  @ViewBuilder private var helpButton: some View {
    if let help {
      KeyedHelp(help, key: .parameter(key, .help), label: .whyThisValue).button
    }
  }

  /// The process's reason in the view's language (ProcessKit's catalog holds every reason).
  private func reason(_ suggestion: Suggestion) -> String {
    ProcessPanelModel.words(reason: suggestion.reason, subject: suggestion.subject, locale: locale)
  }

  private func words(_ value: ParamValue) -> String {
    switch value {
    // A suggestion is read, not typed: four decimals at most.
    case .number(let number): LocaleNumber.decimal(number, locale: locale, maxFractionDigits: 4)
    case .flag(let flag):
      String(localized: flag ? .app("On", locale: locale) : .app("Off", locale: locale))
    case .choice(let option): option
    case .points: ""
    case .text(let text): text
    }
  }

  private func number(_ fallback: Double, _ bounds: ClosedRange<Double>) -> Binding<ParameterValue>
  {
    Binding(
      get: {
        let value = if case .number(let number) = model.params[spec.id] { number } else { fallback }
        // The slider spans the head when the process sizes it; the field accepts the schema.
        return ParameterValue(
          default: fallback, range: model.range(for: spec) ?? bounds, limits: bounds, value: value)
      },
      set: { model.set(spec.id, .number($0.value)) })
  }

  private var flag: Binding<Bool> {
    Binding(
      get: { model.params[spec.id] == .flag(true) },
      set: { model.set(spec.id, .flag($0)) })
  }

  private var text: Binding<String> {
    Binding(
      get: { model.params.text(spec.id) },
      set: { model.set(spec.id, .text($0)) })
  }

  /// A choice among `options`, each greyed with why when the panel says so.
  private func picker(_ options: [String]) -> some View {
    HStack {
      Picker(selection: choice) {
        ForEach(options, id: \.self) { option in
          if let reason = model.unavailableOptions[spec.id]?[option] {
            // Greyed with why; a value already chosen stays chosen (R2).
            Text(.app("\(option) — \(String(localized: reason))")).tag(option)
              .selectionDisabled()
          } else {
            Text(verbatim: option).tag(option)
          }
        }
      } label: {
        Text(label)
      }
      .accessible(.parameter(key, .choice), label: label)
      helpButton
    }
  }

  private var choice: Binding<String> {
    Binding(
      get: { if case .choice(let option) = model.params[spec.id] { option } else { "" } },
      set: { model.set(spec.id, .choice($0)) })
  }

  private func points(_ maxCount: Int) -> Binding<CurveEditorPoints> {
    Binding(
      get: {
        let points: [SIMD2<Double>]? =
          if case .points(let points) = model.params[spec.id] {
            points.map { SIMD2($0.x, $0.y) }
          } else { nil }
        return CurveEditorPoints(points: points, maxCount: maxCount)
      },
      set: { model.set(spec.id, .points($0.points.map { CurvePoint($0.x, $0.y) })) })
  }
}
