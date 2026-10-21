/// A parameter's value as a row edits it: within its range, reset to its default exactly.
///
/// `isDefault` compares exactly, never with a tolerance: an untouched default stays
/// byte-identical, and the badge says so (R2: values applied = values shown).
package struct ParameterValue: Equatable, Sendable {
  /// The value applied.
  package private(set) var value: Double
  /// The value of an untouched preset.
  package let defaultValue: Double
  /// What the slider and the field accept.
  package let range: ClosedRange<Double>

  /// A parameter at `value` (its default when `nil`); the default and the value are clamped to
  /// `range`, so a reset never leaves the slider's range.
  package init(default defaultValue: Double, range: ClosedRange<Double>, value: Double? = nil) {
    let clamped = min(max(defaultValue, range.lowerBound), range.upperBound)
    self.defaultValue = clamped
    self.range = range
    self.value = clamped
    set(value ?? clamped)
  }

  /// The value is the default, bit for bit.
  package var isDefault: Bool { value == defaultValue }

  /// Sets `newValue` clamped to the range.
  package mutating func set(_ newValue: Double) {
    value = min(max(newValue, range.lowerBound), range.upperBound)
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
