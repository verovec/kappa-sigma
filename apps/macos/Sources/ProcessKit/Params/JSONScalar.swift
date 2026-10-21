internal import Foundation

/// Strict reads of `JSONSerialization` scalars: a JSON boolean is never a number and a number never
/// a boolean (`NSNumber` bridges `1` to `true` and `true` to `1`), so a hand-edited file is refused
/// rather than reinterpreted.
enum JSONScalar {
  // swiftlint:disable discouraged_optional_boolean
  /// `value` when it is a JSON boolean; `nil` when it is anything else (the caller refuses it).
  static func bool(_ value: Any?) -> Bool? {
    guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
      return nil
    }
    return number.boolValue
  }
  // swiftlint:enable discouraged_optional_boolean

  /// `value` when it is a JSON integer: not a boolean, no fraction, within the range of `Int`.
  static func int(_ value: Any?) -> Int? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
      return nil
    }
    // Exactly an Int: no fraction, inside Int's range (1e300 is refused, never wrapped).
    return Int(exactly: number.doubleValue)
  }
}
