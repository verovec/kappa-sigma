/// A parameter's value as a row edits it: within its range, reset to its default exactly.
///
/// `isDefault` compares exactly, never with a tolerance: an untouched default stays
/// byte-identical, and the badge says so (R2: values applied = values shown).
package struct ParameterValue: Equatable, Sendable {
  /// The value applied.
  package private(set) var value: Double
  /// The value of an untouched preset.
  package let defaultValue: Double
  /// What the slider spans.
  package let range: ClosedRange<Double>
  /// What the field and `set` accept: the range, or wider when the slider spans only the useful
  /// part of what is valid (the crops on the image, card 0104).
  package let limits: ClosedRange<Double>

  /// A parameter at `value` (its default when `nil`); the default and the value are clamped to
  /// `limits` (`range` when `nil`), so a reset never leaves what the field accepts.
  package init(
    default defaultValue: Double, range: ClosedRange<Double>, limits: ClosedRange<Double>? = nil,
    value: Double? = nil
  ) {
    let limits = limits ?? range
    let clamped = min(max(defaultValue, limits.lowerBound), limits.upperBound)
    self.defaultValue = clamped
    self.range = range.clamped(to: limits)
    self.limits = limits
    self.value = clamped
    set(value ?? clamped)
  }

  /// The value is the default, bit for bit.
  package var isDefault: Bool { value == defaultValue }

  /// Sets `newValue` clamped to the limits.
  package mutating func set(_ newValue: Double) {
    value = min(max(newValue, limits.lowerBound), limits.upperBound)
  }

  /// Sets `newValue` from the slider or its arrows, clamped to the slider's range (`slider`, the
  /// range a drag began on, or `range`): only typed text goes past it.
  package mutating func slide(_ newValue: Double, on slider: ClosedRange<Double>? = nil) {
    let slider = slider ?? range
    set(min(max(newValue, slider.lowerBound), slider.upperBound))
  }

  /// Back to the default.
  package mutating func reset() {
    value = defaultValue
  }

  /// Applies the field's `text` unless it still shows the value (`format(value)`): leaving a field
  /// untouched never rewrites a value the format rounds. `false` when nothing was applied.
  package mutating func commitEdit(
    _ text: String, format: (Double) -> String, parse: (String) -> Double?
  ) -> Bool {
    text == format(value) ? false : commit(text, parse: parse)
  }

  /// Applies `text` read with `parse`, clamped; `false` leaves the value as it was.
  package mutating func commit(_ text: String, parse: (String) -> Double?) -> Bool {
    guard let parsed = parse(text), parsed.isFinite else { return false }
    set(parsed)
    return true
  }
}

extension ClosedRange where Bound == Double {
  /// This range stretched to hold every one of `values`: a slider always shows the value it
  /// edits and its default, even outside the range it normally spans.
  package func widened(toHold values: [Double]) -> ClosedRange<Double> {
    let low = Swift.min(lowerBound, values.min() ?? lowerBound)
    let high = Swift.max(upperBound, values.max() ?? upperBound)
    return low...high
  }
}
