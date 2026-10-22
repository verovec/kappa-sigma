package import Foundation
package import SwiftUI

/// One parameter of a process or a preset: label, slider, a field in the user's notation, reset,
/// the default badge, and its help: the one-line « why » on hover, the card on click (0086).
///
/// RenderKit never imports the app: the caller passes `format` and `parse` (the app's
/// `AstroFormat.parameter` and `parameter(parsing:)`, which round-trip exactly). With a `step`,
/// the focused slider moves one step per arrow, a tenth with ⇧ or ⌥, and an ⌥-drag runs at a
/// tenth of the pointer's travel (card 0085); without one the row is the plain slider it was.
package struct ParameterRow: View {
  /// Where an ⌥-drag's gearing began: the value and the pointer then.
  private struct Gearing: Equatable {
    let anchor: Double
    let start: Double
  }

  private let label: LocalizedStringResource
  @Binding private var parameter: ParameterValue
  private let help: HelpContent?
  private let frozen: Bool
  private let format: (Double) -> String
  private let parse: (String) -> Double?
  private let key: String
  private let step: ParameterStep?
  @State private var text = ""
  @State private var dragging = false
  @State private var fineHeld = false
  @State private var gearing: Gearing?
  @FocusState private var editing: Bool

  /// A row editing `parameter`; `help` is its « ? » (summary on hover, content on click);
  /// `key` (the parameter's stable id) identifies its controls (`AccessibilityID.parameter`);
  /// `frozen` disables the value's controls but never the « ? »; `step` enables the keyboard
  /// and fine-drag steps.
  package init(
    _ label: LocalizedStringResource, parameter: Binding<ParameterValue>,
    help: HelpContent? = nil, key: String, frozen: Bool = false, step: ParameterStep? = nil,
    format: @escaping (Double) -> String, parse: @escaping (String) -> Double?
  ) {
    self.key = key
    self.label = label
    _parameter = parameter
    self.help = help
    self.frozen = frozen
    self.step = step
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
      controls.disabled(frozen)
    }
    .onAppear { text = format(parameter.value) }
    // The slider and reset move the value while the field may have focus: always show it.
    .onChange(of: parameter.value) { text = format(parameter.value) }
    // A freeze takes the focus too: that loss of focus commits nothing (R2).
    .onChange(of: editing) { if !editing && !frozen { commit() } }
    // A freeze (a run starting) shows the applied value, never a typed one nobody committed.
    .onChange(of: frozen) {
      if frozen {
        editing = false
        text = format(parameter.value)
      }
    }
  }

  /// The label, its « why », the default badge and reset.
  private var header: some View {
    HStack(spacing: DesignMetrics.spacingS) {
      Text(label)
      if let help {
        KeyedHelp(help, key: .parameter(key, .help), label: .whyThisValue).button
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
      .disabled(parameter.isDefault || frozen)
      .help(Text(.renderKit("Reset to default")))
      .accessible(.parameter(key, .reset), label: .renderKit("Reset to default"))
    }
  }

  /// The slider and the typed field, the same value.
  private var controls: some View {
    HStack(spacing: DesignMetrics.spacingS) {
      stepped(
        Slider(
          value: Binding(get: { parameter.value }, set: { slide(to: $0) }),
          in: parameter.range, label: { Text(label) },
          onEditingChanged: { active in
            dragging = active
            gearing = nil
          }
        )
        .labelsHidden()
      )
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

  /// With a step: the slider takes focus, arrows move it, ⌥ is tracked for the drag gearing.
  @ViewBuilder private func stepped<Content: View>(_ slider: Content) -> some View {
    if let step {
      slider
        .focusable()
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
          let fine = !press.modifiers.isDisjoint(with: [.shift, .option])
          parameter.set(
            step.moved(parameter.value, forward: press.key == .rightArrow, fine: fine))
          return .handled
        }
        .onModifierKeysChanged(mask: .option) { _, held in fineHeld = !held.isEmpty }
    } else {
      slider
    }
  }

  /// The slider's value: as dragged, or geared down to a tenth of the travel while ⌥ is held.
  ///
  /// The gearing re-anchors where ⌥ was pressed or released, so the value never jumps.
  private func slide(to pointer: Double) {
    guard let step, dragging, fineHeld else {
      gearing = nil
      parameter.set(pointer)
      return
    }
    let gearing = self.gearing ?? Gearing(anchor: parameter.value, start: pointer)
    self.gearing = gearing
    parameter.set(
      step.fineDragValue(anchor: gearing.anchor, start: gearing.start, pointer: pointer))
  }

  /// The field's text applied, then shown as the value it became (clamped, or unchanged).
  private func commit() {
    _ = parameter.commitEdit(text, format: format, parse: parse)
    text = format(parameter.value)
  }
}
