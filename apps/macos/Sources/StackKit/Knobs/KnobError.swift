/// Why a knob patch was refused: nothing of it is applied.
package enum KnobError: Error, Equatable, Sendable {
  /// No knob has this id.
  case unknown(String)
  /// The value is not of the knob's kind, outside its bounds, or not one of its choices.
  case invalid(id: String, value: String)
  /// A lane's patch sets a knob the shared canvas reads (card 0121).
  case runWide(String)
}
