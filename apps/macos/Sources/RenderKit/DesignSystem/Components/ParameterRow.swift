package import Foundation
package import SwiftUI

/// One parameter of a process or a preset: label, slider, a field in the user's notation, reset,
/// the default badge, and its help: the one-line « why » on hover, the card on click (0086).
///
/// RenderKit never imports the app: the caller passes `format` and `parse` (the app's
/// `AstroFormat.parameter` and `parameter(parsing:)`, which round-trip exactly). Every row steps
/// (cards 0085, 0179): by the panel's `step`, else `ParameterStep.default(for:)` of its range.
/// ↑/↓ in the field or on the focused slider move one step per press and speed up while held
/// (`ArrowRepeat`); ←/→ on the slider move one step per press; ⇧ or ⌥ a fine step; an ⌥-drag
/// runs at a tenth of the pointer's travel. The field shows the value applied at once (R2).
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
  /// The slider's range while a drag runs: a range that widens to hold the value would otherwise
  /// move under the pointer.
  @State private var dragRange: ClosedRange<Double>?
  /// The repeats of the ↑/↓ held down, for the speed-up.
  @State private var arrows = ArrowRepeat()
  /// The value the last arrow wrote, until the binding shows it: auto-repeats arrive before the
  /// row is drawn again, and stepping from the binding then would step from a stale value.
  @State private var pending: Double?
  @FocusState private var editing: Bool

  /// A row editing `parameter`; `help` is its « ? » (summary on hover, content on click);
  /// `key` (the parameter's stable id) identifies its controls (`AccessibilityID.parameter`);
  /// `frozen` disables the value's controls but never the « ? »; `step` is the panel's keyboard
  /// and fine-drag step (`nil`: a hundredth of the range, on a decade).
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
    .onChange(of: parameter.value) {
      pending = nil
      text = format(parameter.value)
    }
    // A freeze takes the focus too: that loss of focus commits nothing (R2).
    .onChange(of: editing) { if !editing && !frozen { commit() } }
    // A freeze (a run starting) shows the applied value, never a typed one nobody committed.
    .onChange(of: frozen) {
      // A row frozen mid-drag gets no end of the drag: the next drag starts on the live range.
      dragRange = nil
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
          in: dragRange ?? parameter.range, label: { Text(label) },
          onEditingChanged: { active in
            dragging = active
            dragRange = active ? parameter.range : nil
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
        // ↑/↓ only: ←/→ still move the caret through what is typed.
        .onKeyPress(keys: [.upArrow, .downArrow], phases: [.down, .repeat, .up]) { press in
          arrow(press, typed: true)
        }
    }
  }

  /// The slider takes focus, arrows move it, ⌥ is tracked for the drag gearing.
  private func stepped<Content: View>(_ slider: Content) -> some View {
    slider
      .focusable()
      .onKeyPress(
        keys: [.leftArrow, .rightArrow, .upArrow, .downArrow], phases: [.down, .repeat, .up]
      ) { press in
        arrow(press, typed: false)
      }
      .onModifierKeysChanged(mask: .option) { _, held in fineHeld = !held.isEmpty }
  }

  /// The row's step: the panel's, else a decade of its range.
  private var arrowStep: ParameterStep { step ?? .default(for: parameter.range) }

  /// One arrow event, applied to the value and shown in the field.
  ///
  /// ↑/↓ move by `ArrowRepeat`'s tier, ←/→ one step per press or repeat.
  /// The step starts from the value the row last wrote (`pending`), else the binding's. From the
  /// field (`typed`), what was typed is applied first. The field then shows the new value (R2).
  private func arrow(_ press: KeyPress, typed: Bool) -> KeyPress.Result {
    let vertical = press.key == .upArrow || press.key == .downArrow
    let phase: ArrowRepeat.Phase =
      press.phase == .up ? .up : press.phase == .repeat ? .repeat : .down
    guard let times = arrows.steps(phase, accelerating: vertical) else {
      return vertical ? .handled : .ignored
    }
    var edited = parameter
    if let pending { edited.set(pending) }
    if typed && text != format(edited.value) { _ = edited.commit(text, parse: parse) }
    let fine = !press.modifiers.isDisjoint(with: [.shift, .option])
    let forward = press.key == .upArrow || press.key == .rightArrow
    edited.nudge(arrowStep.moved(edited.value, forward: forward, fine: fine, times: times))
    parameter = edited
    pending = edited.value
    text = format(edited.value)
    return .handled
  }

  /// The slider's value: as dragged, or geared down to a tenth of the travel while ⌥ is held.
  ///
  /// The gearing re-anchors where ⌥ was pressed or released, so the value never jumps.
  private func slide(to pointer: Double) {
    guard dragging, fineHeld else {
      gearing = nil
      parameter.slide(pointer, on: dragRange)
      return
    }
    let gearing = self.gearing ?? Gearing(anchor: parameter.value, start: pointer)
    self.gearing = gearing
    parameter.slide(
      arrowStep.fineDragValue(anchor: gearing.anchor, start: gearing.start, pointer: pointer),
      on: dragRange)
  }

  /// The field's text applied, then shown as the value it became (clamped, or unchanged).
  private func commit() {
    pending = nil
    _ = parameter.commitEdit(text, format: format, parse: parse)
    text = format(parameter.value)
  }
}
