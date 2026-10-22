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
        format: { AstroFormat(locale: locale).parameter($0) },
        parse: { AstroFormat(locale: locale).parameter(parsing: $0) })
    case .flag:
      HStack {
        Toggle(isOn: flag) { Text(label) }
          .accessible(.parameter(key, .toggle), label: label)
        helpButton
      }
    case .choice(_, let options):
      HStack {
        Picker(selection: choice) {
          ForEach(options, id: \.self) { Text(verbatim: $0).tag($0) }
        } label: {
          Text(label)
        }
        .accessible(.parameter(key, .choice), label: label)
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
    String(localized: ProcessKitResources.title(suggestion.reason, locale: locale))
  }

  private func words(_ value: ParamValue) -> String {
    switch value {
    // A suggestion is read, not typed: four decimals at most.
    case .number(let number): LocaleNumber.decimal(number, locale: locale, maxFractionDigits: 4)
    case .flag(let flag):
      String(localized: flag ? .app("On", locale: locale) : .app("Off", locale: locale))
    case .choice(let option): option
    case .points: ""
    }
  }

  private func number(_ fallback: Double, _ bounds: ClosedRange<Double>) -> Binding<ParameterValue>
  {
    Binding(
      get: {
        let value = if case .number(let number) = model.params[spec.id] { number } else { fallback }
        return ParameterValue(default: fallback, range: bounds, value: value)
      },
      set: { model.set(spec.id, .number($0.value)) })
  }

  private var flag: Binding<Bool> {
    Binding(
      get: { model.params[spec.id] == .flag(true) },
      set: { model.set(spec.id, .flag($0)) })
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
