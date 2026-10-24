import Foundation
import RenderKit
import Testing

/// A parameter row's value: clamped to its range, typed in the user's notation, reset to the
/// default exactly — the default badge shows only for the untouched value (R2: values applied =
/// values shown).
@Suite("ParameterRow — reset, default badge, typed values")
struct ParameterRowTests {
  static func french(_ text: String) -> Double? {
    Double(text.replacing(",", with: "."))
  }

  @Test("reset restores the default exactly and brings the default badge back")
  func testResetRestoresDefaultAndShowsBadge() {
    var parameter = ParameterValue(default: 0.115, range: 0...1)
    #expect(parameter.isDefault)
    #expect(ParameterRow.badge(for: parameter) != nil)

    parameter.set(0.2)
    #expect(!parameter.isDefault)
    #expect(ParameterRow.badge(for: parameter) == nil)

    parameter.reset()
    #expect(parameter.value == 0.115)
    #expect(parameter.isDefault)
    #expect(ParameterRow.badge(for: parameter) != nil)
  }

  struct Typed: Sendable, CustomTestStringConvertible {
    let text: String
    let accepted: Bool
    let value: Double
    var testDescription: String { "\"\(text)\"" }
  }

  @Test(
    "a typed value is parsed, clamped to the range, or refused without changing the value",
    arguments: [
      Typed(text: "0,25", accepted: true, value: 0.25),
      Typed(text: "1,5", accepted: true, value: 1),
      Typed(text: "-3", accepted: true, value: 0),
      Typed(text: "abc", accepted: false, value: 0.115),
      Typed(text: "", accepted: false, value: 0.115),
    ])
  func testCommitTypedText(_ row: Typed) {
    var parameter = ParameterValue(default: 0.115, range: 0...1)
    #expect(parameter.commit(row.text, parse: Self.french) == row.accepted)
    #expect(parameter.value == row.value)
  }

  @Test("a value set outside the range is clamped, a value at the default is the default")
  func testSetClamps() {
    var parameter = ParameterValue(default: 0.5, range: 0...1, value: 3)
    #expect(parameter.value == 1)
    parameter.set(0.5)
    #expect(parameter.isDefault)
    parameter.set(-1)
    #expect(parameter.value == 0)
  }

  static func threeDigits(_ value: Double) -> String {
    LocaleNumber.decimal(value, locale: Locale(identifier: "en"), maxFractionDigits: 3)
  }

  @Test("a value the field rounds stays exact when the field is left untouched")
  func testUntouchedFieldKeepsValue() {
    var parameter = ParameterValue(default: 0.812_34, range: 0...1)
    let shown = Self.threeDigits(parameter.value)
    let applied = parameter.commitEdit(shown, format: Self.threeDigits) { Double($0) }
    #expect(!applied)
    #expect(parameter.value == 0.812_34 && parameter.isDefault)
  }

  @Test("an edited field applies its text")
  func testEditedFieldApplies() {
    var parameter = ParameterValue(default: 0.5, range: 0...1)
    let applied = parameter.commitEdit("0.25", format: Self.threeDigits) { Double($0) }
    #expect(applied)
    #expect(parameter.value == 0.25)
  }

  @Test("a default outside the range is clamped once, so reset stays in range and is default")
  func testDefaultOutsideRange() {
    var parameter = ParameterValue(default: 2, range: 0...1)
    #expect(parameter.value == 1 && parameter.isDefault)
    parameter.set(0.3)
    parameter.reset()
    #expect(parameter.value == 1 && parameter.isDefault)
  }

  @Test("a typed value past the slider is kept up to the limits; the slider's range stays")
  func testLimitsWiderThanRange() {
    var parameter = ParameterValue(default: 0, range: 0...7, limits: 0...100_000, value: 20)
    #expect(parameter.value == 20, "a value within the limits is never clamped to the slider")

    let applied = parameter.commit("30") { Double($0) }
    #expect(applied)
    #expect(parameter.value == 30 && parameter.range == 0...7)
    parameter.set(200_000)
    #expect(parameter.value == 100_000)
  }

  @Test("the slider and its arrows stop at the slider's ends; only typed text goes past them")
  func testSlideStaysOnTheSlider() {
    var parameter = ParameterValue(default: 0, range: 0...7, limits: 0...100_000, value: 7)

    parameter.slide(8)
    #expect(parameter.value == 7)
    parameter.slide(-1)
    #expect(parameter.value == 0)
    let applied = parameter.commit("20") { Double($0) }
    #expect(applied && parameter.value == 20)
    parameter.slide(15, on: 0...20)
    #expect(parameter.value == 15, "a drag keeps the range it began on")
  }

  @Test("a default inside the limits but off the slider stays the default, bit for bit")
  func testDefaultWithinLimits() {
    let parameter = ParameterValue(default: 10, range: 0...7, limits: 0...100)
    #expect(parameter.defaultValue == 10 && parameter.value == 10 && parameter.isDefault)
  }

  @Test(
    "a slider's range widens to hold the value and the default, never narrows",
    arguments: [
      (0.0...7.0, [3.0, 0.0], 0.0...7.0), (0.0...7.0, [20.0, 0.0], 0.0...20.0),
      (0.5...1.0, [0.3, 0.8], 0.3...1.0),
    ])
  func testWidenedToHold(range: ClosedRange<Double>, values: [Double], want: ClosedRange<Double>) {
    #expect(range.widened(toHold: values) == want)
  }

  @Test("a slider range wider than the limits is cut to them")
  func testRangeWithinLimits() {
    let parameter = ParameterValue(default: 0, range: 0...200, limits: 0...100)
    #expect(parameter.range == 0...100)
  }
}
