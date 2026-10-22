import Foundation
import RenderKit
import Testing

/// `STFChannelControls`, the model behind `STFControls`: shadows in σ, target background and
/// highlights over one channel's `STFParameters`, the raw numbers beside them, every control
/// with its documented step (arrows = 1 step, ⇧-arrows and ⌥-drag = 1/10) — card 0085.
@Suite("STFControls — steps, typed fields, derived values")
struct STFControlsTests {
  static let mapping = STFMapping(median: 0.1, madn: 0.014_826)
  static let auto = mapping.parameters(sigma: -2.8, targetBackground: 0.25)
  static func controls() -> STFChannelControls {
    STFChannelControls(parameters: auto, auto: auto, mapping: mapping)
  }

  struct Step: Sendable, CustomTestStringConvertible {
    let control: STFChannelControls.Control
    let coarse: Double
    let range: ClosedRange<Double>
    /// A typed value outside the range, away from the autostretch's end of it.
    let typed: String
    let clamped: Double
    var testDescription: String { "\(control)" }
  }

  @Test(
    "each control's step and range are the documented ones; a typed value is clamped and shown",
    arguments: [
      Step(control: .shadowsSigma, coarse: 0.1, range: -5...5, typed: "99", clamped: 5),
      Step(
        control: .targetBackground, coarse: 0.01, range: 0.01...0.6, typed: "99", clamped: 0.6),
      Step(control: .highlights, coarse: 0.01, range: 0.5...1, typed: "-1", clamped: 0.5),
      Step(control: .rawShadows, coarse: 0.0001, range: 0...1, typed: "99", clamped: 1),
      Step(control: .rawMidtone, coarse: 0.001, range: 0...1, typed: "99", clamped: 1),
      Step(control: .rawHighlights, coarse: 0.01, range: 0...1, typed: "-1", clamped: 0),
    ])
  func testStepsAndFields(_ row: Step) {
    let step = STFChannelControls.step(of: row.control)
    #expect(step.coarse == row.coarse)
    #expect(abs(step.fine - row.coarse / 10) < 1e-15)
    #expect(step.delta(forward: true, fine: false) == row.coarse)
    #expect(step.delta(forward: false, fine: true) == -step.fine)
    #expect(STFChannelControls.range(of: row.control) == row.range)

    var controls = Self.controls()
    #expect(controls[row.control].isDefault, "seeded from the autostretch: every row is default")
    #expect(controls[row.control].range == row.range)

    // A typed value outside the range is clamped and shown as what it became.
    var typed = controls[row.control]
    let accepted = typed.commit(row.typed, parse: { Double($0) })
    #expect(accepted)
    #expect(typed.value == row.clamped)
    controls[row.control] = typed
    #expect(controls[row.control].value == row.clamped)
    #expect(!controls[row.control].isDefault)
    let shown = STFControls.format(
      controls[row.control].value, control: row.control, locale: Locale(identifier: "en"))
    #expect(STFControls.parse(shown, locale: Locale(identifier: "en")) == row.clamped)
  }

  @Test("⌥-drag moves the value by a tenth of the pointer's travel from where the drag began")
  func testFineDrag() {
    let step = ParameterStep(0.1)
    #expect(abs(step.fineDragValue(anchor: 0.5, start: 0.5, pointer: 0.7) - 0.52) < 1e-12)
    #expect(abs(step.fineDragValue(anchor: 0.5, start: 0.5, pointer: 0.1) - 0.46) < 1e-12)
    #expect(step.fineDragValue(anchor: 0.5, start: 0.5, pointer: 0.5) == 0.5)
    // ⌥ pressed mid-drag: the gearing starts where the pointer is, the value where it was.
    #expect(abs(step.fineDragValue(anchor: 0.7, start: 0.7, pointer: 0.9) - 0.72) < 1e-12)
  }

  @Test("one σ step moves the black point by a tenth of a MADN and leaves the midtone alone")
  func testSigmaStepMovesShadowsOnly() {
    var controls = Self.controls()
    var sigma = controls[.shadowsSigma]
    sigma.set(sigma.value + STFChannelControls.step(of: .shadowsSigma).coarse)
    controls[.shadowsSigma] = sigma
    #expect(abs(controls.parameters.shadows - Self.mapping.shadows(sigma: -2.7)) < 1e-12)
    #expect(controls.parameters.midtone == Self.auto.midtone)
    #expect(controls.parameters.highlights == Self.auto.highlights)
    #expect(abs(controls[.shadowsSigma].value + 2.7) < 1e-9)
    // The readouts follow: the raw c0 shows the new black point, the target drifted.
    #expect(controls[.rawShadows].value == controls.parameters.shadows)
    #expect(controls[.targetBackground].value != 0.25)
  }

  @Test("the target background sets the midtone so the median shows at that level")
  func testTargetBackgroundSetsMidtone() {
    var controls = Self.controls()
    var target = controls[.targetBackground]
    target.set(0.4)
    controls[.targetBackground] = target
    // Siril's meaning: MTF(m, median − c0) — not rescaled by c1 − c0.
    let level = MTF.apply(
      controls.parameters.midtone, Self.mapping.median - controls.parameters.shadows)
    #expect(abs(level - 0.4) < 1e-9)
    #expect(controls.parameters.shadows == Self.auto.shadows)
    #expect(abs(controls[.targetBackground].value - 0.4) < 1e-9)
  }

  @Test("the raw rows edit c0, m and c1 directly and the derived rows read them back")
  func testRawRowsEditParameters() {
    var controls = Self.controls()
    var raw = controls[.rawMidtone]
    raw.set(0.3)
    controls[.rawMidtone] = raw
    #expect(controls.parameters.midtone == 0.3)
    var highlights = controls[.highlights]
    highlights.set(0.9)
    controls[.highlights] = highlights
    #expect(controls.parameters.highlights == 0.9 && controls[.rawHighlights].value == 0.9)
    var shadows = controls[.rawShadows]
    shadows.set(0.05)
    controls[.rawShadows] = shadows
    #expect(controls.parameters.shadows == 0.05)
    #expect(abs(controls[.shadowsSigma].value - Self.mapping.sigma(ofShadows: 0.05)) < 1e-12)
  }

  @Test("reset on a derived row returns that parameter to its autostretch value exactly")
  func testResetRowRestoresAuto() {
    var controls = Self.controls()
    var sigma = controls[.shadowsSigma]
    sigma.set(1)
    controls[.shadowsSigma] = sigma
    #expect(controls.parameters.shadows != Self.auto.shadows)
    sigma = controls[.shadowsSigma]
    sigma.reset()
    controls[.shadowsSigma] = sigma
    #expect(controls.parameters.shadows == Self.auto.shadows)
    #expect(controls[.shadowsSigma].isDefault)
  }

  @Test("every control has a label, a « why » and a format with enough digits for its step")
  func testWordsAndDigits() {
    for control in STFChannelControls.Control.allCases {
      let digits = STFChannelControls.digits(of: control)
      let fine = STFChannelControls.step(of: control).fine
      #expect(Double(sign: .plus, exponent: 0, significand: 1) / pow(10, Double(digits)) <= fine)
      let text = STFControls.format(
        0.123_456_789, control: control, locale: Locale(identifier: "fr"))
      #expect(text.contains(","))
      #expect(STFControls.parse(text, locale: Locale(identifier: "fr")) != nil)
    }
  }
  @Test(
    "a raw number outside a derived row's slider widens the row so what is shown is what is applied"
  )
  func testRowShowsTheNumberApplied() {
    var controls = Self.controls()
    var raw = controls[.rawHighlights]
    raw.set(0.3)
    controls[.rawHighlights] = raw
    #expect(controls[.highlights].value == 0.3)
    #expect(controls[.highlights].range.lowerBound == 0.3)
    #expect(controls[.highlights].range.upperBound == 1)
    var shadows = controls[.rawShadows]
    shadows.set(0.9)
    controls[.rawShadows] = shadows
    let sigma = controls[.shadowsSigma]
    #expect(sigma.value == Self.mapping.sigma(ofShadows: 0.9) && sigma.value > 5)
    #expect(sigma.range.upperBound == sigma.value)
  }

  @Test("with the black point at or above the median the target row is disabled and inert")
  func testTargetNeedsTheMedianAboveBlack() {
    var controls = Self.controls()
    #expect(controls.targetAvailable)
    var sigma = controls[.shadowsSigma]
    sigma.set(1)
    controls[.shadowsSigma] = sigma
    #expect(!controls.targetAvailable)
    let midtone = controls.parameters.midtone
    var target = controls[.targetBackground]
    target.set(0.3)
    controls[.targetBackground] = target
    #expect(controls.parameters.midtone == midtone, "the edit is ignored, the display stays")
    #expect(controls.parameters.midtone > 0, "never the all-white m = 0")
  }

  @Test("after the black point moved, resetting the target reads back as its default")
  func testTargetResetAfterShadowsMoved() {
    var controls = Self.controls()
    var sigma = controls[.shadowsSigma]
    sigma.set(-2)
    controls[.shadowsSigma] = sigma
    #expect(!controls[.targetBackground].isDefault)
    var target = controls[.targetBackground]
    target.reset()
    controls[.targetBackground] = target
    #expect(controls[.targetBackground].isDefault)
    #expect(controls[.targetBackground].value == 0.25)
    #expect(
      abs(
        Self.mapping.targetBackground(
          ofMidtone: controls.parameters.midtone, shadows: controls.parameters.shadows) - 0.25)
        < 1e-9)
  }

  @Test(
    "typed numbers in the locale's notation: decimal mark, either minus, spaces, grouping",
    arguments: zip(
      ["−2,50", "0,229", "1 234,5", "-0.5", "abc", "1.234,5"],
      [-2.5, 0.229, 1234.5, -0.5, nil, nil]))
  func testParseLocaleNumbers(text: String, expected: Double?) {
    let french = Locale(identifier: "fr_FR")
    #expect(STFControls.parse(text, locale: french) == expected)
    #expect(LocaleNumber.parse(text, locale: french) == expected)
  }
}
