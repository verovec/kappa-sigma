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
