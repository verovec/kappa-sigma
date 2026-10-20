/// Numbers read from headers, sidecars and names, never trapping on user data.
///
/// `NaN`, `inf` and values past `Int`'s range read as absent (Go's float→int conversion did not
/// panic either).
enum LegacyNumber {
  /// The finite value `text` spells, or `nil`.
  static func finite(_ text: some StringProtocol) -> Double? {
    guard let value = Double(String(text)), value.isFinite else { return nil }
    return value
  }

  /// `value × scale`, rounded half away from zero, or `nil` when it does not fit an `Int`.
  static func rounded(_ value: Double, scale: Double = 1) -> Int? {
    let scaled = (value * scale).rounded()
    guard scaled.isFinite, abs(scaled) < 9.2e18 else { return nil }
    return Int(scaled)
  }

  /// `value` truncated toward zero (Go's `int64(f)`), or `nil` when it does not fit an `Int`.
  static func truncated(_ value: Double) -> Int? {
    guard value.isFinite, abs(value) < 9.2e18 else { return nil }
    return Int(value)
  }
}
