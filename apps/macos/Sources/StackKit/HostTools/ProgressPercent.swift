/// The percentage a tool's output line carries: the legacy `(\d+)\s?%` rule shared by the Siril
/// and GraXpert readers, quirks included (`100.00%` reads 0: the leftmost match is `00%`).
package enum ProgressPercent {
  /// The first `N%` of `text` when it is at most 100, else nil.
  package static func first(in text: String) -> Int? {
    guard let range = text.range(of: #"(\d+)\s?%"#, options: .regularExpression) else { return nil }
    let digits = text[range].prefix { $0.isNumber }
    guard let value = Int(digits), value <= 100 else { return nil }
    return value
  }
}
