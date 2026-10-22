import RenderKit
import Testing

/// An arrow press lands on the fine step's grid (card 0089): repeated small steps read as the
/// decimals typed, never as accumulated float error.
@Suite("ParameterStep — arrow presses on the fine grid")
struct ParameterStepTests {
  @Test("three fine presses of 0.0001 read 0.0003; coarse and backward presses stay on the grid")
  func testMovedSnapsToGrid() {
    let step = ParameterStep(0.001)
    var value = 0.0
    for _ in 0..<3 { value = step.moved(value, forward: true, fine: true) }
    #expect(value == 0.0003)
    #expect(step.moved(0.0003, forward: false, fine: false) == -0.0007)
    #expect(ParameterStep(0.01).moved(0.5, forward: true, fine: true) == 0.501)
  }
}

extension ParameterStepTests {
  @Test("a large or non-decimal step never gives NaN, and keeps its own decimals")
  func testMovedLargeSteps() {
    #expect(ParameterStep(25).moved(0, forward: true, fine: true) == 2.5)
    #expect(ParameterStep(25).moved(2.5, forward: true, fine: false) == 27.5)
    #expect(ParameterStep(3).moved(0.3, forward: true, fine: true) == 0.6)
    #expect(ParameterStep(1).moved(0.25, forward: false, fine: false) == -0.75)
  }
}

extension ParameterStepTests {
  @Test("a typed value keeps its own decimals across presses")
  func testMovedKeepsTypedDecimals() {
    #expect(ParameterStep(0.001).moved(0.00035, forward: true, fine: false) == 0.00135)
    var value = 0.12345
    for _ in 0..<3 { value = ParameterStep(0.01).moved(value, forward: true, fine: true) }
    #expect(value == 0.12645)
  }
}
