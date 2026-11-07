import AppKit
import Foundation
import RenderKit
import SwiftUI
import Testing

/// ↑/↓ on a parameter row (card 0179): a press moves one step, a held key moves faster, ←/→ stay
/// one step per press; the field shows the value applied at once (R2).
///
/// The row lives in a real window with its field (or slider) first responder, and the keys go
/// through `NSWindow.sendEvent`, as typing does: the test proves the field editor hands ↑/↓ to
/// the row instead of moving its caret.
@MainActor
@Suite("ParameterRow keys — ↑/↓ step and accelerate, ←/→ one step", .serialized)
struct ParameterRowKeyTests {
  /// The value a row edits, read back by the test.
  final class Box {
    var value: ParameterValue
    init(_ value: ParameterValue) { self.value = value }
  }

  /// A row over `box` in an offscreen window, laid out and shown.
  struct Hosted {
    let window: NSWindow
    let host: NSView
    let box: Box

    /// The row's text field (the only `NSTextField` that edits).
    func field() throws -> NSTextField {
      try #require(Self.views(in: host).compactMap { $0 as? NSTextField }.first { $0.isEditable })
    }

    /// Every view under `view`, depth first.
    static func views(in view: NSView) -> [NSView] {
      [view] + view.subviews.flatMap(views(in:))
    }

    /// Gives the field the keyboard, as a click in it does.
    func focusField() throws {
      let field = try field()
      #expect(window.makeFirstResponder(field))
      settle()
    }

    /// Lets SwiftUI see the focus and the value changes.
    func settle() {
      host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.05))
      host.layoutSubtreeIfNeeded()
    }

    /// Sends `key` (one of the four arrows) down, `repeats` auto-repeats, then up.
    func press(
      _ key: Arrow, repeats: Int = 0, modifiers: NSEvent.ModifierFlags = [], release: Bool = true
    ) throws {
      for index in 0...repeats {
        window.sendEvent(try key.event(.keyDown, repeat: index > 0, modifiers, in: window))
        settle()
      }
      if release {
        window.sendEvent(try key.event(.keyUp, repeat: false, modifiers, in: window))
        settle()
      }
    }

    /// The field's text as shown.
    func text() throws -> String { try field().stringValue }
  }

  /// The four arrows, with their key codes and the function-key characters AppKit sends.
  enum Arrow {
    case up, down, left, right

    var keyCode: UInt16 {
      switch self {
      case .up: 126
      case .down: 125
      case .left: 123
      case .right: 124
      }
    }

    var character: String {
      let scalar: Int =
        switch self {
        case .up: NSUpArrowFunctionKey
        case .down: NSDownArrowFunctionKey
        case .left: NSLeftArrowFunctionKey
        case .right: NSRightArrowFunctionKey
        }
      // The arrows' function-key scalars (U+F700…U+F703) are valid: the fallback never shows.
      return Unicode.Scalar(UInt32(scalar)).map { String(Character($0)) } ?? ""
    }

    func event(
      _ type: NSEvent.EventType, repeat isARepeat: Bool, _ modifiers: NSEvent.ModifierFlags,
      in window: NSWindow
    ) throws -> NSEvent {
      try #require(
        NSEvent.keyEvent(
          with: type, location: .zero, modifierFlags: modifiers.union([.function, .numericPad]),
          timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
          context: nil, characters: character, charactersIgnoringModifiers: character,
          isARepeat: isARepeat, keyCode: keyCode))
    }
  }

  /// The row as a panel shows it: the value lives in view state, so every change re-renders the
  /// row; `box` mirrors it for the test to read.
  struct Host: View {
    let box: Box
    let step: ParameterStep?
    /// The model rounds what it is sent, as a whole-number Stacking knob does.
    let rounds: Bool
    @State private var value: ParameterValue

    init(box: Box, step: ParameterStep?, rounds: Bool = false) {
      self.box = box
      self.step = step
      self.rounds = rounds
      _value = State(initialValue: box.value)
    }

    var body: some View {
      ParameterRow(
        .renderKit("Hα blend"),
        parameter: Binding(
          get: { value },
          set: { sent in
            var kept = sent
            if rounds { kept.set(sent.value.rounded()) }
            value = kept
          }),
        key: "keys", step: step, format: { String($0) }, parse: { Double($0) }
      )
      .padding()
      .onChange(of: value) { box.value = value }
    }
  }

  /// A row over a binding the test builds: one that lags, or one that refuses.
  struct BindingHost: View {
    let binding: Binding<ParameterValue>

    var body: some View {
      ParameterRow(
        .renderKit("Hα blend"), parameter: binding, key: "keys",
        format: { String($0) }, parse: { Double($0) }
      )
      .padding()
    }
  }

  /// A row over `value` in a window; `step` as a panel would pass it.
  static func hosted(
    _ value: ParameterValue, step: ParameterStep? = nil, rounds: Bool = false
  ) -> Hosted {
    let box = Box(value)
    return hosted(box, Host(box: box, step: step, rounds: rounds))
  }

  /// `view` in an offscreen window, `box` holding what the test reads.
  static func hosted(_ box: Box, _ view: some View) -> Hosted {
    let host = NSHostingView(rootView: view)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 420, height: 140), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    let hosted = Hosted(window: window, host: host, box: box)
    hosted.settle()
    return hosted
  }

  @Test("↑ in the field moves the value one step and the field shows it")
  func testArrowKeysOnField_OnePressOneStep() throws {
    let row = Self.hosted(ParameterValue(default: 0.5, range: 0...1))
    defer { row.window.close() }
    try row.focusField()
    try row.press(.up)
    #expect(row.box.value.value == 0.51)
    #expect(try row.text() == "0.51")
    try row.press(.down)
    try row.press(.down)
    #expect(row.box.value.value == 0.49)
    #expect(try row.text() == "0.49")
  }
}
