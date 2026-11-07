import AstroStackApp
import RenderKit
import StackKit
import Testing

/// The Stacking knobs' arrow step (card 0179): a whole-number knob moves one per press, ⇧ too;
/// a decimal knob takes its range's decade, as every row without a declared step.
extension KnobPanelViewModelTests {
  @Test("every whole-number knob steps by one, ⇧ included; decimal knobs take the row default")
  func testKnobSteps() throws {
    let panel = KnobPanelViewModel(mode: .deepsky)
    let numbers = panel.rows.compactMap { row -> (KnobPanelViewModel.Row, Bool)? in
      guard case .number(_, let integer) = row.kind else { return nil }
      return (row, integer)
    }
    #expect(numbers.contains { $0.1 } && numbers.contains { !$0.1 }, "both kinds exist")
    for (row, integer) in numbers {
      if integer {
        let step = try #require(row.step, "\(row.id)")
        #expect(step.coarse == 1 && step.fine == 1, "\(row.id)")
      } else {
        #expect(row.step == nil, "\(row.id) takes ParameterStep.default")
      }
    }
  }
}
