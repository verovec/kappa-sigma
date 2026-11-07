import AppKit
import RenderKit
import SwiftUI
import Testing

/// The row against bindings that are not the truth at once: one that lags behind a held key,
/// one the model refuses, one it rounds; and typed text that does not read (card 0179, R2).
extension ParameterRowKeyTests {
  @Test("a held key steps from what it wrote, though the binding still shows the old value")
  func testHeldKeyStepsFromItsOwnWrites() throws {
    let box = Box(ParameterValue(default: 0, range: 0...1))
    let snapshot = box.value
    let row = Self.hosted(
      box, BindingHost(binding: Binding(get: { snapshot }, set: { box.value = $0 })))
    defer { row.window.close() }
    try row.focusField()
    try row.press(.up, repeats: 15, release: false)
    #expect(box.value.value == 0.24, "8 × 1 + 8 × 2 steps, never restarted from 0")
    #expect(try row.text() == "0.24")
  }

  @Test("a write the model refuses leaves the field showing the value kept, once released")
  func testRefusedWriteIsNotShown() throws {
    let box = Box(ParameterValue(default: 0.5, range: 0...1))
    let row = Self.hosted(box, BindingHost(binding: Binding(get: { box.value }, set: { _ in })))
    defer { row.window.close() }
    try row.focusField()
    try row.press(.up)
    #expect(try row.text() == "0.5")
    try row.press(.up)
    #expect(box.value.value == 0.5 && box.value.isDefault)
    #expect(try row.text() == "0.5", "the second press built on nothing that was refused")
  }

  @Test("a whole-number knob reads 4 after 3.4 typed and ↑, as the model keeps it")
  func testWholeKnobFromATypedFraction() throws {
    let row = Self.hosted(
      ParameterValue(default: 2, range: 0...512), step: .default(for: 0...512, integer: true),
      rounds: true)
    defer { row.window.close() }
    try row.focusField()
    let editor = try #require(row.window.firstResponder as? NSTextView)
    editor.selectAll(nil)
    editor.insertText("3.4", replacementRange: editor.selectedRange())
    row.settle()
    try row.press(.up)
    #expect(row.box.value.value == 4)
    #expect(try row.text() == "4.0")
  }

  @Test("typed text that does not read as a number blocks the step and stays to be fixed")
  func testUnreadableTypedTextBlocksTheStep() throws {
    let row = Self.hosted(ParameterValue(default: 0.5, range: 0...1))
    defer { row.window.close() }
    try row.focusField()
    let editor = try #require(row.window.firstResponder as? NSTextView)
    editor.selectAll(nil)
    editor.insertText("0.3x", replacementRange: editor.selectedRange())
    row.settle()
    try row.press(.up)
    #expect(row.box.value.value == 0.5 && row.box.value.isDefault)
    #expect(try row.text() == "0.3x")
  }
}
