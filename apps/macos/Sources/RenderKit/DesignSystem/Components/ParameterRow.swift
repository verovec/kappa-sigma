package import Foundation
package import SwiftUI

/// One parameter of a process or a preset: label, slider, a field in the user's notation, reset,
/// the default badge, and its help: the one-line « why » on hover, the card on click (0086).
///
/// RenderKit never imports the app: the caller passes `format` and `parse` (the app's
/// `AstroFormat.parameter` and `parameter(parsing:)`, which round-trip exactly). Every field steps
/// (cards 0085, 0179): ↑/↓ move one step per press and speed up while held (`ArrowRepeat`), by
/// the panel's `step`, else `ParameterStep.default(for:)` of the range; ⇧ or ⌥ a fine step; ⌘
/// and ⌃ stay the field's (⌘↑ to the start). With a declared `step` the slider takes focus too: ←/→ one step per press,
/// ↑/↓ as in the field, and an ⌥-drag runs at a tenth of the pointer's travel. The field shows
/// the value applied (R2).
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
  /// The value the last arrow wrote while its key is held.
  ///
  /// Auto-repeats arrive before the binding shows a write (whatever the binding), and stepping
  /// from it then would step from a stale value. A new press starts from the binding again.
  @State private var pending: Double?
  /// Arrow releases: each one shows the binding's value again, once the row is drawn, so a write
  /// the model rounded or refused never stays in the field (R2).
  @State private var releases = 0
  @FocusState private var editing: Bool

  /// A row editing `parameter`; `help` is its « ? » (summary on hover, content on click);
  /// `key` (the parameter's stable id) identifies its controls (`AccessibilityID.parameter`);
  /// `frozen` disables the value's controls but never the « ? »; `step` is the panel's keyboard
  /// and fine-drag step (`nil`: the field steps by `ParameterStep.default(for:)` of the range,
  /// and the slider stays out of the tab loop).
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
    // After a release the binding is the truth again: what the model kept, rounded or refused.
    // Only after an arrow wrote: a blocked step leaves the text typed as it was.
    .task(id: releases) {
      guard releases > 0, pending != nil else { return }
      pending = nil
      text = format(parameter.value)
    }
    // A freeze takes the focus too: that loss of focus commits nothing (R2).
    // A field left while an arrow is held shows the binding: its text is the arrow's, not typed.
    .onChange(of: editing) {
      if editing || frozen {
        return
      } else if pending != nil {
        pending = nil
        text = format(parameter.value)
      } else {
        commit()
      }
    }
    // A freeze (a run starting) shows the applied value, never a typed one nobody committed.
    .onChange(of: frozen) {
      // A row frozen mid-drag gets no end of the drag: the next drag starts on the live range.
      // Nor the release of a held arrow: the next press starts afresh.
      dragRange = nil
      pending = nil
      arrows = ArrowRepeat()
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

  /// With a declared step the slider takes focus, arrows move it, ⌥ is tracked for the gearing;
  /// without one it stays out of the tab loop, as it was (the field still steps).
  @ViewBuilder private func stepped<Content: View>(_ slider: Content) -> some View {
    if step != nil {
      slider
        .focusable()
        .onKeyPress(
          keys: [.leftArrow, .rightArrow, .upArrow, .downArrow], phases: [.down, .repeat, .up]
        ) { press in
          arrow(press, typed: false)
        }
        .onModifierKeysChanged(mask: .option) { _, held in fineHeld = !held.isEmpty }
    } else {
      slider
    }
  }

  /// The row's step: the panel's, else a decade of its range.
  private var arrowStep: ParameterStep { step ?? .default(for: parameter.limits) }

  /// One arrow event, applied to the value and shown in the field.
  ///
  /// ↑/↓ move by `ArrowRepeat`'s tier, ←/→ one step per press or repeat. A repeat starts from
  /// the value the row last wrote (`pending`), a press from the binding's. From the field (`typed`),
  /// what was typed is applied first; text that does not read as a number blocks the step and
  /// stays for the user to fix, never replaced by another value.
  private func arrow(_ press: KeyPress, typed: Bool) -> KeyPress.Result {
    let vertical = press.key == .upArrow || press.key == .downArrow
    let phase = ArrowRepeat.Phase(press.phase)
    // A release counts whatever the modifiers: it shows the binding again (R2).
    guard let times = arrows.steps(phase, accelerating: vertical) else {
      releases &+= 1
      return vertical ? .handled : .ignored
    }
    guard press.modifiers.isDisjoint(with: [.command, .control]) else { return .ignored }
    if phase == .down { pending = nil }
    var edited = parameter
    if let pending { edited.set(pending) }
    if typed && text != format(edited.value) {
      guard edited.commit(text, parse: parse) else { return .handled }
    }
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
    guard let step, dragging, fineHeld else {
      gearing = nil
      // A whole-number row never gets a fraction from its slider either.
      parameter.slide(step?.whole == true ? pointer.rounded() : pointer, on: dragRange)
      return
    }
    let gearing = self.gearing ?? Gearing(anchor: parameter.value, start: pointer)
    self.gearing = gearing
    parameter.slide(
      step.fineDragValue(anchor: gearing.anchor, start: gearing.start, pointer: pointer),
      on: dragRange)
  }

  /// The field's text applied, then shown as the value it became (clamped, or unchanged).
  private func commit() {
    pending = nil
    _ = parameter.commitEdit(text, format: format, parse: parse)
    text = format(parameter.value)
  }
}

extension ArrowRepeat.Phase {
  /// The phase of a SwiftUI key press.
  fileprivate init(_ phase: KeyPress.Phases) {
    self = phase == .up ? .up : phase == .repeat ? .repeat : .down
  }
}
