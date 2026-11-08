package import RenderKit
internal import StackKit

extension KnobPanelViewModel.Row {
  /// The arrow step of a number knob (card 0179), `nil` for a flag or a choice.
  ///
  /// One per press for a whole number, which the schema refuses a fraction of (⇧ too); a decade
  /// of its bounds for a decimal one. Every number knob has one, so every slider of the Stacking
  /// panel takes the keyboard alike.
  package var step: ParameterStep? {
    guard case .number(let bounds, let integer) = kind else { return nil }
    return integer ? .wholeNumber : .default(for: bounds)
  }
}
