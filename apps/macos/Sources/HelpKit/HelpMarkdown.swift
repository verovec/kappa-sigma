/// The Markdown subset help content is written in (card 0061, R3: « juste ce qu'il faut »).
///
/// Each non-blank line is a paragraph, or a list item when it starts with `- `, `* ` or `1. `;
/// inside it, `**bold**` and `*italic*` / `_italic_`. Anything else — headings, links, code,
/// quotes, an unclosed marker — stays plain text: the renderer never fails on content.
package enum HelpMarkdown {
  /// A run of text with its emphasis.
  package struct Run: Equatable, Sendable {
    /// The text.
    package let text: String
    /// Bold.
    package let bold: Bool
    /// Italic.
    package let italic: Bool

    /// `text` with its emphasis.
    package init(_ text: String, bold: Bool, italic: Bool) {
      self.text = text
      self.bold = bold
      self.italic = italic
    }
  }

  /// A line of content.
  package enum Block: Equatable, Sendable {
    /// A paragraph.
    case paragraph([Run])
    /// A list item.
    case item([Run])

    /// Its runs.
    package var runs: [Run] {
      switch self {
      case .paragraph(let runs), .item(let runs): runs
      }
    }
  }

  /// The blocks of `source`.
  package static func parse(_ source: String) -> [Block] {
    // `isNewline`, not "\n": a CRLF file's "\r\n" is one Character.
    source.split(whereSeparator: \.isNewline).compactMap { raw in
      let line = raw.trimmingCharacters(in: .whitespaces)
      guard !line.isEmpty else { return nil }
      if let rest = listItem(line) { return .item(runs(rest)) }
      return .paragraph(runs(line))
    }
  }

  /// The text after a list marker, if `line` is a list item.
  private static func listItem(_ line: String) -> String? {
    for marker in ["- ", "* "] where line.hasPrefix(marker) {
      return String(line.dropFirst(marker.count))
    }
    let digits = line.prefix { $0.isNumber }
    if !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") {
      return String(line.dropFirst(digits.count + 2))
    }
    return nil
  }

  /// The runs of `text`: closed emphasis markers apply, others stay text.
  static func runs(_ text: String) -> [Run] {
    var runs: [Run] = []
    var plain = ""
    var rest = Substring(text)
    // The source character before `rest` (a closing marker counts), for the intraword rule.
    var previous: Character?
    while !rest.isEmpty {
      if let (inner, after, bold) = emphasis(in: rest, previous: previous) {
        if !plain.isEmpty { runs.append(Run(plain, bold: false, italic: false)) }
        plain = ""
        runs.append(Run(String(inner), bold: bold, italic: !bold))
        previous = rest[rest.index(before: after.startIndex)]
        rest = after
      } else {
        // An unclosed `**` is text as a whole, never a `*` opening an italic.
        let count = rest.hasPrefix("**") ? 2 : 1
        plain += rest.prefix(count)
        previous = rest.prefix(count).last
        rest = rest.dropFirst(count)
      }
    }
    if !plain.isEmpty { runs.append(Run(plain, bold: false, italic: false)) }
    return runs
  }

  /// The closed emphasis at the start of `text`: its content, what follows, whether bold.
  ///
  /// `**…**`, `*…*` or `_…_`, hugging its content (`2 * 3 * 4` is text); an underscore inside a
  /// word (`snake_case`) is text.
  private static func emphasis(in text: Substring, previous: Character?) -> (
    Substring, Substring, Bool
  )? {
    for marker in ["**", "*", "_"] where text.hasPrefix(marker) {
      if marker == "_", let previous, previous.isLetter || previous.isNumber { return nil }
      let body = text.dropFirst(marker.count)
      guard let close = body.range(of: marker), close.lowerBound > body.startIndex,
        body.first?.isWhitespace == false,
        body[body.index(before: close.lowerBound)].isWhitespace == false
      else { return nil }
      let after = body[close.upperBound...]
      if marker == "_", let next = after.first, next.isLetter || next.isNumber { return nil }
      return (body[..<close.lowerBound], after, marker == "**")
    }
    return nil
  }
}
