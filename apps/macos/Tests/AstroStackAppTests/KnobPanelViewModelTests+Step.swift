import AstroStackApp
import RenderKit
import StackKit
import Testing

/// The Stacking knobs' arrow step (card 0179): a whole-number knob moves one per press, ⇧ too;
/// a decimal knob a decade of its bounds. Every number knob has one, so the panel's sliders
/// all take the keyboard alike.
extension KnobPanelViewModelTests {
  @Test("every whole-number knob steps by one, ⇧ included; decimal knobs by their bounds' decade")
  func testKnobSteps() throws {
    let panel = KnobPanelViewModel(mode: .deepsky)
    let numbers = panel.rows.compactMap { row -> (KnobPanelViewModel.Row, Bool)? in
      guard case .number(_, let integer) = row.kind else { return nil }
      return (row, integer)
    }
    #expect(numbers.contains { $0.1 } && numbers.contains { !$0.1 }, "both kinds exist")
    for (row, integer) in numbers {
      let step = try #require(row.step, "\(row.id)")
      guard case .number(let bounds, _) = row.kind else { continue }
      #expect(step == (integer ? .wholeNumber : .default(for: bounds)), "\(row.id)")
    }
  }
}
