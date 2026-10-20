/// The `printf` specifiers of a catalog string, as Foundation formats them.
package enum FormatSpecifiers {
  /// A specifier and where it sits in its text.
  package struct Match: Equatable, Sendable {
    /// The specifier without its positional index (`%1$@` → `%@`).
    package var specifier: String
    /// Where the specifier sits, `%` and positional index included.
    package var range: Range<String.Index>
  }

  private static let flags: Set<Character> = ["-", "+", " ", "0", "#", "'"]
  private static let lengths: Set<Character> = ["h", "l", "q", "L", "z", "t", "j"]
  private static let conversions: Set<Character> = Set("@dDiuUxXoOfFeEgGaAcCsSp")

  /// The specifiers of `text` in order; `%%` is a literal percent sign, not a specifier.
  package static func of(_ text: String) -> [String] {
    matches(in: text).map(\.specifier)
  }

  /// Every specifier of `text` with its range.
  package static func matches(in text: String) -> [Match] {
    var found: [Match] = []
    var index = text.startIndex
    while let percent = text[index...].firstIndex(of: "%") {
      let (specifier, end) = specifier(in: text, at: percent)
      if let specifier { found.append(Match(specifier: specifier, range: percent..<end)) }
      index = end
    }
    return found
  }

  /// The specifier starting at `percent`, and where scanning resumes.
  private static func specifier(
    in text: String, at percent: String.Index
  ) -> (String?, String.Index) {
    var index = text.index(after: percent)
    guard index < text.endIndex else { return (nil, index) }
    if text[index] == "%" { return (nil, text.index(after: index)) }
    // Positional argument `n$`, dropped: the order of arguments is the key's.
    var digits = index
    while digits < text.endIndex, text[digits].isNumber { digits = text.index(after: digits) }
    if digits < text.endIndex, text[digits] == "$", digits > index {
      index = text.index(after: digits)
    }
    var body = "%"
    while index < text.endIndex {
      let char = text[index]
      index = text.index(after: index)
      if flags.contains(char) || char.isNumber || char == "." || lengths.contains(char) {
        body.append(char)
      } else if conversions.contains(char) {
        return (body + String(char), index)
      } else {
        return (nil, index)
      }
    }
    return (nil, index)
  }
}
