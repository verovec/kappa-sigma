import AppKit
import RenderKit
import Testing

/// A panel's declared step. The SwiftUI slider draws itself (no `NSSlider` to make first
/// responder), so its ←/→ rule is pinned by `ArrowRepeatTests.testHorizontalNeverAccelerates`:
/// the row calls the same `arrow(_:typed:)` from the slider and from the field.
extension ParameterRowKeyTests {
  @Test("a panel's own step wins over the range's")
  func testDeclaredStepWins() throws {
    let row = Self.hosted(ParameterValue(default: 0, range: 0...1), step: ParameterStep(0.1))
    defer { row.window.close() }
    try row.focusField()
    try row.press(.up)
    #expect(row.box.value.value == 0.1)
  }
}
