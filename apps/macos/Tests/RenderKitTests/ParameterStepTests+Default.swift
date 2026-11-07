import RenderKit
import Testing

/// Every row gets a step (card 0179): the one a panel declares, else a decade of its range.
extension ParameterStepTests {
  @Test(
    "a row without a declared step moves by about a hundredth of its range, on a decade",
    arguments: [
      (0.0...1.0, false, 0.01),
      (-5.0...5.0, false, 0.1),
      (0.0...64.0, false, 1.0),
      (0.001...0.5, false, 0.01),
      (0.0...0.45, false, 0.01),
      (0.0...512.0, true, 1.0),
      (1.0...4.0, true, 1.0),
      (0.0...0.0, false, 1.0),
    ])
  func testDefaultStepFollowsTheRange(range: ClosedRange<Double>, integer: Bool, coarse: Double) {
    #expect(ParameterStep.default(for: range, integer: integer).coarse == coarse)
  }

  @Test("a whole-number step has no fraction to give: ⇧ moves a whole step too")
  func testIntegerStepHasNoFineFraction() {
    let step = ParameterStep.default(for: 0...512, integer: true)
    #expect(step.fine == 1)
    #expect(step.moved(3, forward: true, fine: true) == 4)
    #expect(ParameterStep(0.01).fine == 0.001, "a decimal step keeps its tenth")
  }

  @Test(
    "several steps at once land on the same grid as single presses",
    arguments: [
      (0.12345, 0.01, true, false, 5, 0.17345),
      (0.5, 0.01, false, false, 10, 0.4),
      (0.0003, 0.001, true, true, 3, 0.0006),
      (2.0, 1.0, true, false, 1, 3.0),
    ])
  func testMovedTimesStaysOnTheGrid(
    value: Double, coarse: Double, forward: Bool, fine: Bool, times: Int, expected: Double
  ) {
    let step = ParameterStep(coarse)
    #expect(step.moved(value, forward: forward, fine: fine, times: times) == expected)
    var pressed = value
    for _ in 0..<times { pressed = step.moved(pressed, forward: forward, fine: fine) }
    #expect(pressed == expected, "one press at a time reads the same")
  }
}
