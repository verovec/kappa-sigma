package import RenderKit
internal import StackKit

extension KnobPanelViewModel.Row {
  /// The arrow step of a number knob (card 0179): one per press for a whole number, which the
  /// schema refuses a fraction of (⇧ too); `nil` for a decimal knob, which takes the row default
  /// (`ParameterStep.default(for:)`, a decade of its range).
  package var step: ParameterStep? {
    guard case .number(let bounds, true) = kind else { return nil }
    return .default(for: bounds, integer: true)
  }
}
