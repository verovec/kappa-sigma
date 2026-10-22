internal import Foundation

/// One line of Siril's output, as the legacy runner reads it, plus the `status:` lines of pipe mode.
package struct SirilLine: Equatable, Sendable {
  /// A pipe-mode `status:` line.
  package enum Status: String, Equatable, Sendable {
    case starting, success, error, exit
  }

  /// The line without a leading `log:` (and at most one whitespace): what the user reads.
  package let text: String
  /// The first `(\d+)\s?%` of the text, when ≤ 100 — the legacy rule, quirks included
  /// (`100.00%` reads 0: the leftmost match is `00%`).
  package let percent: Int?
  /// The status of a `status: <word> …` line.
  package let status: Status?

  /// A line from its parts.
  package init(text: String, percent: Int?, status: Status?) {
    self.text = text
    self.percent = percent
    self.status = status
  }

  /// Parses one raw output line.
  package init(parsing raw: String) {
    let text = raw.replacingOccurrences(of: #"^log:\s?"#, with: "", options: .regularExpression)
    self.text = text
    self.percent = ProgressPercent.first(in: text)
    if raw.hasPrefix("status:") {
      let word = raw.dropFirst("status:".count).split(separator: " ").first.map(String.init)
      self.status = word.flatMap(Status.init(rawValue:))
    } else {
      self.status = nil
    }
  }
}
