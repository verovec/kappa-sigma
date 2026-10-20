internal import Foundation

/// The cards of a FITS primary header, in file order, each kept as its original 80 characters.
package struct FITSHeader: Equatable, Sendable {
  /// One 80-character card.
  package struct Card: Equatable, Sendable {
    /// The original 80 characters, written back unchanged.
    package let raw: String

    /// Columns 1–8, trimmed.
    package var keyword: String {
      String(raw.prefix(8)).trimmingCharacters(in: .whitespaces)
    }

    /// The value of a `KEY     = value / comment` card, without quotes or comment; `nil` for
    /// cards without `= ` in columns 9–10 (COMMENT, HISTORY, blank).
    package var value: String? {
      let chars = Array(raw)
      guard chars.count >= 10, chars[8] == "=", chars[9] == " " else { return nil }
      let rest = String(chars[10...]).trimmingCharacters(in: .whitespaces)
      guard rest.hasPrefix("'") else {
        let number = rest.split(separator: "/", maxSplits: 1).first ?? ""
        return number.trimmingCharacters(in: .whitespaces)
      }
      return Self.quoted(Array(rest.dropFirst()))
    }

    /// A FITS string: up to the closing quote, `''` standing for one quote, trailing spaces
    /// not significant (FITS 4.2.1).
    private static func quoted(_ chars: [Character]) -> String {
      var text = ""
      var index = 0
      while index < chars.count {
        if chars[index] == "'" {
          guard index + 1 < chars.count, chars[index + 1] == "'" else { break }
          index += 1
        }
        text.append(chars[index])
        index += 1
      }
      return String(text.reversed().drop(while: { $0 == " " }).reversed())
    }
  }

  /// Every card before `END`, in order.
  package let cards: [Card]

  /// The first card named `keyword`, as text (quotes and trailing spaces removed).
  package func string(_ keyword: String) -> String? {
    cards.first { $0.keyword == keyword }?.value
  }

  /// The first card named `keyword`, as a number (`D` exponents accepted).
  package func double(_ keyword: String) -> Double? {
    string(keyword).flatMap { Double($0.replacingOccurrences(of: "D", with: "E")) }
  }

  /// The first card named `keyword`, as an integer.
  package func int(_ keyword: String) -> Int? {
    string(keyword).flatMap { Int($0) ?? double(keyword).flatMap { Int(exactly: $0) } }
  }
}
