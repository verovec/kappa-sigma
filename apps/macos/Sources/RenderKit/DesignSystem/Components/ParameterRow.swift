package import Foundation
package import SwiftUI

/// One parameter of a process or a preset: label, slider, a field in the user's notation, reset,
/// the default badge, and its help: the one-line « why » on hover, the card on click (0086).
///
/// RenderKit never imports the app: the caller passes `format` and `parse` (the app's
/// `AstroFormat.parameter` and `parameter(parsing:)`, which round-trip exactly).
package struct ParameterRow: View {
  private let label: LocalizedStringResource
  @Binding private var parameter: ParameterValue
  private let help: HelpContent?
  private let format: (Double) -> String
  private let parse: (String) -> Double?
  private let key: String
  @State private var text = ""
  @FocusState private var editing: Bool

  /// A row editing `parameter`; `help` is its « ? » (summary on hover, content on click);
  /// `key` (the parameter's stable id) identifies its controls (`AccessibilityID.parameter`).
  package init(
    _ label: LocalizedStringResource, parameter: Binding<ParameterValue>,
    help: HelpContent? = nil, key: String, format: @escaping (Double) -> String,
    parse: @escaping (String) -> Double?
  ) {
    self.key = key
    self.label = label
    _parameter = parameter
    self.help = help
    self.format = format
    self.parse = parse
  }

  /// The badge of an untouched default, `nil` once the value moved.
  nonisolated package static func badge(
    for parameter: ParameterValue, locale: Locale? = nil
  ) -> LocalizedStringResource? {
    parameter.isDefault ? .renderKit("Default", locale: locale) : nil
  }

  package var body: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingXS) {
      header
      controls
    }
    .onAppear { text = format(parameter.value) }
    // The slider and reset move the value while the field may have focus: always show it.
    .onChange(of: parameter.value) { text = format(parameter.value) }
    .onChange(of: editing) { if !editing { commit() } }
  }

  /// The label, its « why », the default badge and reset.
  private var header: some View {
    HStack(spacing: DesignMetrics.spacingS) {
      Text(label)
      if let help {
        HelpButton(
          summary: help.summary, label: .whyThisValue, key: .parameter(key, .help)
        ) {
          help.content()
        }
      }
      Spacer(minLength: DesignMetrics.spacingS)
      if let badge = Self.badge(for: parameter) {
        Text(badge)
          .font(.caption)
          .foregroundStyle(DesignColor.textSecondary.color)
          .padding(.horizontal, DesignMetrics.spacingXS)
          .padding(.vertical, DesignMetrics.spacingXXS)
          .overlay(Capsule().strokeBorder(DesignColor.textSecondary.color.opacity(0.5)))
      }
      Button {
        parameter.reset()
      } label: {
        Image(systemName: "arrow.counterclockwise")
      }
      .buttonStyle(.borderless)
      .disabled(parameter.isDefault)
      .help(Text(.renderKit("Reset to default")))
      .accessible(.parameter(key, .reset), label: .renderKit("Reset to default"))
    }
  }

  /// The slider and the typed field, the same value.
  private var controls: some View {
    HStack(spacing: DesignMetrics.spacingS) {
      Slider(
        value: Binding(get: { parameter.value }, set: { parameter.set($0) }),
        in: parameter.range
      ) {
        Text(label)
      }
      .labelsHidden()
      .accessible(.parameter(key, .slider), label: label)
      TextField(text: $text) { Text(label) }
        .labelsHidden()
        .accessible(.parameter(key, .field), label: label)
        .font(DesignMetrics.valueFont)
        .multilineTextAlignment(.trailing)
        .frame(width: 84)
        .focused($editing)
        .onSubmit(commit)
    }
  }

  /// The field's text applied, then shown as the value it became (clamped, or unchanged).
  private func commit() {
    _ = parameter.commitEdit(text, format: format, parse: parse)
    text = format(parameter.value)
  }
}
