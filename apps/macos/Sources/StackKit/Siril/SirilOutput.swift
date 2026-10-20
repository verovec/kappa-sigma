internal import Foundation

/// Turns a failed run's log into the one-line reason shown to the user (`sirilErrorHint`).
package enum SirilOutput {
  private static let keywords = [
    "error", "not found", "failed", "do not allow", "cannot", "could not", "invalid",
    "not enough", "no space", "abort",
  ]
  /// How far above `Error in line N` the cause is looked for.
  private static let causeLookback = 8

  /// The cause of a failure: the lines just before Siril's `Error in line N` locator, or else
  /// the last three lines carrying an error keyword; empty when nothing looks like an error.
  package static func errorHint(log: String) -> String {
    let lines = log.split(separator: "\n", omittingEmptySubsequences: false)
      .map { $0.replacingOccurrences(of: #"^log:\s?"#, with: "", options: .regularExpression) }
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
    return hintAtLocator(lines) ?? hintByKeywords(lines)
  }

  private static func isLocator(_ line: String) -> Bool {
    line.range(of: #"^error in line \d+"#, options: [.regularExpression, .caseInsensitive]) != nil
  }

  private static func isNoise(_ line: String) -> Bool {
    let lower = line.lowercased()
    let prefixes = [
      "progress:", "reading sequence failed", "searching for sequences",
      "finalizing sequence processing failed",
    ]
    return prefixes.contains { lower.hasPrefix($0) } || lower.contains("succeeded")
      || lower.contains("script execution failed")
  }

  private static func hintAtLocator(_ lines: [String]) -> String? {
    guard let last = lines.lastIndex(where: isLocator) else { return nil }
    var cause: [String] = []
    var index = last - 1
    while index >= 0, index >= last - causeLookback, cause.count < 3 {
      if !isNoise(lines[index]) && !isLocator(lines[index]) { cause.insert(lines[index], at: 0) }
      index -= 1
    }
    return (cause + [lines[last]]).joined(separator: "; ")
  }

  private static func hintByKeywords(_ lines: [String]) -> String {
    var matches: [String] = []
    var noise: [String] = []
    for line in lines {
      let lower = line.lowercased()
      guard keywords.contains(where: { lower.contains($0) }) else { continue }
      if isNoise(line) { noise.append(line) } else { matches.append(line) }
    }
    return (matches.isEmpty ? noise : matches).suffix(3).joined(separator: "; ")
  }
}
