/// The string literals of a Swift source, as written, with the argument label before each.
///
/// Not a Swift parser: it skips comments, reads `"…"` literals with their interpolations
/// (literals nested in an interpolation are reported too) and ignores multi-line and raw
/// strings, which the house does not use for UI text.
package enum SourceLiterals {
  /// One literal: its content between the quotes, its line, and the label it is passed to.
  package struct Literal: Equatable, Sendable {
    package var content: String
    package var line: Int
    /// `systemImage` in `Label("…", systemImage: "folder")` for the second literal.
    package var label: String?

    /// A literal holding `content` (as written) on `line`, passed to `label`.
    package init(content: String, line: Int, label: String?) {
      self.content = content
      self.line = line
      self.label = label
    }
  }

  /// Every literal of `source`, in order.
  package static func of(_ source: String) -> [Literal] {
    var lexer = Lexer(chars: Array(source))
    return lexer.literals()
  }

  private struct Lexer {
    let chars: [Character]
    var index = 0
    var line = 1
    var found: [Literal] = []

    init(chars: [Character]) { self.chars = chars }

    mutating func literals() -> [Literal] {
      while index < chars.count { step() }
      return found
    }

    private func peek(_ offset: Int = 0) -> Character? {
      index + offset < chars.count ? chars[index + offset] : nil
    }

    private mutating func step() {
      switch (chars[index], peek(1), peek(2)) {
      case ("/", "/", _): skip(until: "\n")
      case ("/", "*", _): skipBlockComment()
      case ("\"", "\"", "\""), ("#", "\"", _): skipRawOrMultiline()
      case ("\"", _, _): readLiteral()
      default: advance()
      }
    }

    private mutating func advance() {
      if chars[index] == "\n" { line += 1 }
      index += 1
    }

    private mutating func skip(until terminator: Character) {
      while index < chars.count, chars[index] != terminator { advance() }
    }

    private mutating func skipBlockComment() {
      while index < chars.count, !(chars[index] == "*" && peek(1) == "/") { advance() }
      index = min(index + 2, chars.count)
    }

    /// Multi-line (`"""`) and raw (`#"`) strings: skipped to their closing delimiter.
    private mutating func skipRawOrMultiline() {
      let multiline = chars[index] == "\""
      index += multiline ? 3 : 2
      while index < chars.count {
        if multiline, chars[index] == "\"", peek(1) == "\"", peek(2) == "\"" {
          index += 3
          return
        }
        if !multiline, chars[index] == "\"", peek(1) == "#" {
          index += 2
          return
        }
        advance()
      }
    }

    /// A `"…"` literal starting at `index`; interpolations are read for nested literals.
    @discardableResult
    private mutating func readLiteral() -> String {
      let start = line
      let label = labelBefore(index)
      index += 1
      var content = ""
      while index < chars.count, chars[index] != "\"", chars[index] != "\n" {
        if chars[index] == "\\", peek(1) == "(" {
          content += "\\("
          index += 2
          content += readInterpolation() + ")"
        } else if chars[index] == "\\", let next = peek(1) {
          content += String(chars[index]) + String(next)
          index += 2
        } else {
          content.append(chars[index])
          index += 1
        }
      }
      // The closing quote, or the line break of an unterminated literal (counted).
      if index < chars.count { advance() }
      found.append(Literal(content: content, line: start, label: label))
      return content
    }

    /// The code of an interpolation up to its closing parenthesis (consumed), reading the
    /// literals nested in it.
    private mutating func readInterpolation() -> String {
      var depth = 1
      var code = ""
      while index < chars.count {
        let char = chars[index]
        if char == "\"" {
          code += "\"" + readLiteral() + "\""
          continue
        }
        index += 1
        if char == "(" { depth += 1 }
        if char == ")" {
          depth -= 1
          if depth == 0 { return code }
        }
        code.append(char)
      }
      return code
    }

    /// The argument label right before the literal at `position` (`label: "…"`), if any.
    private func labelBefore(_ position: Int) -> String? {
      var cursor = position - 1
      while cursor >= 0, chars[cursor].isWhitespace { cursor -= 1 }
      guard cursor >= 0, chars[cursor] == ":" else { return nil }
      cursor -= 1
      var name = ""
      while cursor >= 0, chars[cursor].isLetter || chars[cursor].isNumber || chars[cursor] == "_" {
        name.insert(chars[cursor], at: name.startIndex)
        cursor -= 1
      }
      return name.isEmpty ? nil : name
    }
  }
}
