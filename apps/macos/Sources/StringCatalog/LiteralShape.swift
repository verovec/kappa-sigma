/// The text of a catalog key and of a Swift string literal reduced to a common shape, so a key
/// can be matched to the literal that produces it without knowing the interpolated types.
///
/// `"Night of %@"` (key) and `"Night of \(session)"` (source) share the shape
/// `Night of ⟨⟩`; `%%` in a key is the `%` of the literal.
package enum LiteralShape {
  /// The placeholder standing for one argument.
  package static let hole = "⟨⟩"

  /// The shape of a catalog key: every specifier becomes a hole.
  package static func ofKey(_ key: String) -> String {
    var shape = ""
    var index = key.startIndex
    for match in FormatSpecifiers.matches(in: key) {
      shape += unescapedPercents(key[index..<match.range.lowerBound]) + hole
      index = match.range.upperBound
    }
    return shape + unescapedPercents(key[index...])
  }

  /// The shape of a literal's content as written in source (escapes not yet processed).
  package static func ofLiteral(_ content: String) -> String {
    var shape = ""
    var chars = content[...]
    while let first = chars.first {
      chars = chars.dropFirst()
      guard first == "\\", let escaped = chars.first else {
        shape.append(first)
        continue
      }
      chars = chars.dropFirst()
      switch escaped {
      case "(":
        chars = skipInterpolation(chars)
        shape += hole
      case "n": shape += "\n"
      case "t": shape += "\t"
      default: shape.append(escaped)
      }
    }
    return shape
  }

  private static func unescapedPercents(_ text: Substring) -> String {
    String(text.replacing("%%", with: "%"))
  }

  /// The characters after an interpolation's closing parenthesis.
  private static func skipInterpolation(_ text: Substring) -> Substring {
    var depth = 1
    var rest = text
    while let char = rest.first, depth > 0 {
      rest = rest.dropFirst()
      if char == "(" { depth += 1 }
      if char == ")" { depth -= 1 }
    }
    return rest
  }
}
