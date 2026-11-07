import AppKit
import RenderKit
import Testing

/// A held ↑/↓ speeds up; ⇧ steps finely; the slider's bounds hold; typed text counts first.
extension ParameterRowKeyTests {
  @Test("a held ↑ moves 8 × 1, 8 × 2, then 8 × 5 steps; a release starts again at one")
  func testArrowKeysOnField_MoveTheBindingWithAcceleration() throws {
    let row = Self.hosted(ParameterValue(default: 0, range: 0...1))
    defer { row.window.close() }
    try row.focusField()
    try row.press(.up, repeats: 23)
    #expect(row.box.value.value == 0.64, "8 + 16 + 40 steps of 0.01")
    #expect(try row.text() == "0.64")
    try row.press(.up)
    #expect(row.box.value.value == 0.65, "a new press moves one step")
  }

  @Test("⇧↑ moves a tenth of a step; ↓ at the slider's low end stays there")
  func testArrowKeysOnField_FineAndBounds() throws {
    let row = Self.hosted(ParameterValue(default: 0, range: 0...1))
    defer { row.window.close() }
    try row.focusField()
    try row.press(.up, modifiers: .shift)
    #expect(row.box.value.value == 0.001)
    try row.press(.down, repeats: 5)
    #expect(row.box.value.value == 0)
    #expect(try row.text() == "0.0")
  }

  @Test("a value typed and not yet entered is applied, then stepped from")
  func testArrowKeysOnField_CommitTypedTextFirst() throws {
    let row = Self.hosted(ParameterValue(default: 0.5, range: 0...1))
    defer { row.window.close() }
    try row.focusField()
    let editor = try #require(row.window.firstResponder as? NSTextView)
    editor.selectAll(nil)
    editor.insertText("0.3", replacementRange: editor.selectedRange())
    row.settle()
    try row.press(.up)
    #expect(row.box.value.value == 0.31)
    #expect(try row.text() == "0.31")
  }

  @Test("←/→ in the field move the caret, never the value")
  func testLeftRightInFieldKeepTheValue() throws {
    let row = Self.hosted(ParameterValue(default: 0.5, range: 0...1))
    defer { row.window.close() }
    try row.focusField()
    try row.press(.left, repeats: 3)
    try row.press(.right)
    #expect(row.box.value.value == 0.5 && row.box.value.isDefault)
  }

  @Test("a value typed past the slider is stepped from where it stands")
  func testArrowKeysPastTheSlider() throws {
    let row = Self.hosted(ParameterValue(default: 10, range: 0...100, limits: 0...400, value: 250))
    defer { row.window.close() }
    try row.focusField()
    try row.press(.down)
    #expect(row.box.value.value == 249, "the default step of 0…100 is 1")
    try row.press(.up, repeats: 3)
    #expect(row.box.value.value == 249, "↑ never goes further past the slider")
  }

  @Test("⌘↑ and ⌃↓ in the field stay the field's: the value does not move")
  func testCommandArrowsStayTheField() throws {
    let row = Self.hosted(ParameterValue(default: 0.5, range: 0...1))
    defer { row.window.close() }
    try row.focusField()
    try row.press(.up, modifiers: .command)
    try row.press(.down, modifiers: .control)
    #expect(row.box.value.value == 0.5 && row.box.value.isDefault)
  }
}
