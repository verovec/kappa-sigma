internal import Foundation

/// Number formatting identical to the legacy engine's Go verbs, so scripts stay byte-identical.
package enum GoFormat {
  /// The shortest text that round-trips, as Go's `strconv.FormatFloat(v, 'g', -1, 64)`.
  ///
  /// Go's shortest `%g` takes the shortest round-trip digits and writes them in `%e` form when
  /// the decimal exponent is < −4 or ≥ 6, in `%f` form otherwise (`1e+06`, `999999`, `1e-05`,
  /// `0.0001`). Exponents have at least two digits; `-0`, `+Inf`, `-Inf` and `NaN` as Go writes.
  package static func shortest(_ value: Double) -> String {
    if value.isNaN { return "NaN" }
    if value.isInfinite { return value > 0 ? "+Inf" : "-Inf" }
    if value == 0 { return value.sign == .minus ? "-0" : "0" }
    let (digits, point) = shortestDigits(abs(value))
    let sign = value < 0 ? "-" : ""
    let exponent = point - 1
    guard exponent < -4 || exponent >= 6 else { return sign + plain(digits, point: point) }
    let head = String(digits.prefix(1))
    let tail = digits.dropFirst()
    let mantissa = tail.isEmpty ? head : head + "." + tail
    let magnitude = abs(exponent)
    return sign + mantissa + "e" + (exponent < 0 ? "-" : "+") + (magnitude < 10 ? "0" : "")
      + String(magnitude)
  }

  /// `fmt.Sprintf("%.Nf", v)`: C rounding of the exact binary value, as Go does.
  package static func fixed(_ value: Double, decimals: Int) -> String {
    String(format: "%.\(decimals)f", value)
  }

  /// The shortest round-trip digits and the decimal point position.
  ///
  /// value = 0.digits × 10^point, digits without leading or trailing zeros. Swift's
  /// `description` already prints the shortest digits.
  private static func shortestDigits(_ value: Double) -> (String, Int) {
    let parts = "\(value)".lowercased().split(separator: "e")
    let exponent = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
    let whole = parts[0].split(separator: ".", omittingEmptySubsequences: false)
    let integer = String(whole[0])
    var digits = integer + (whole.count > 1 ? String(whole[1]) : "")
    var point = integer.count + exponent
    while digits.first == "0" {
      digits.removeFirst()
      point -= 1
    }
    while digits.last == "0" { digits.removeLast() }
    return (digits, point)
  }

  /// Plain decimal text of `digits` with the decimal point at `point`.
  private static func plain(_ digits: String, point: Int) -> String {
    if point <= 0 { return "0." + String(repeating: "0", count: -point) + digits }
    if point >= digits.count {
      return digits + String(repeating: "0", count: point - digits.count)
    }
    let index = digits.index(digits.startIndex, offsetBy: point)
    return "\(digits[..<index]).\(digits[index...])"
  }
}
