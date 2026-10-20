internal import Foundation

/// Reads target declarations out of a `Package.swift` text.
///
/// Not a Swift parser: it relies on the house layout of `Package.swift` (one call per target,
/// literal names, no trailing comments inside a target) and is pinned by a fixture manifest.
/// Running `swift package dump-package` from a test would deadlock on the `.build` lock.
package enum ManifestParser {
  private static let calls: [(String, DeclaredTarget.Kind)] = [
    (".executableTarget(", .executable), (".testTarget(", .test), (".target(", .library),
  ]

  /// The targets declared in `manifest`, in order.
  package static func targets(in manifest: String) -> [DeclaredTarget] {
    let text = Array(withoutLineComments(manifest))
    var targets: [DeclaredTarget] = []
    var index = 0
    while index < text.count {
      guard let (kind, open) = call(in: text, at: index),
        let close = matching(text, open: open, opener: "(", closer: ")")
      else {
        index += 1
        continue
      }
      let body = String(text[(open + 1)..<close])
      if let name = firstLiteral(after: "name:", in: body) {
        targets.append(
          DeclaredTarget(name: name, kind: kind, dependencies: dependencies(in: body)))
      }
      index = close + 1
    }
    return targets
  }

  // MARK: - Lexing

  private static func withoutLineComments(_ text: String) -> String {
    text.split(separator: "\n", omittingEmptySubsequences: false)
      .filter { !$0.trimmingPrefix(while: \.isWhitespace).hasPrefix("//") }
      .joined(separator: "\n")
  }

  /// The declaration call starting at `index`, and the index of its opening parenthesis.
  private static func call(in text: [Character], at index: Int) -> (DeclaredTarget.Kind, Int)? {
    for (token, kind) in calls where text[index...].starts(with: token) {
      return (kind, index + token.count - 1)
    }
    return nil
  }

  /// The index of the bracket closing the one at `open`, skipping string literals.
  private static func matching(
    _ text: [Character], open: Int, opener: Character, closer: Character
  ) -> Int? {
    var depth = 0
    var inString = false
    for index in open..<text.count {
      let char = text[index]
      if char == "\"" { inString.toggle() }
      guard !inString else { continue }
      if char == opener { depth += 1 }
      if char == closer { depth -= 1 }
      if depth == 0 { return index }
    }
    return nil
  }

  // MARK: - Fields

  private static func firstLiteral(after label: String, in body: String) -> String? {
    guard let range = body.range(of: label) else { return nil }
    return literals(in: String(body[range.upperBound...])).first?.value
  }

  /// Every name in `dependencies: [...]`, except the package of a `.product(…)`.
  private static func dependencies(in body: String) -> [String] {
    guard let range = body.range(of: "dependencies:") else { return [] }
    let rest = Array(body[range.upperBound...])
    guard let open = rest.firstIndex(of: "["),
      let close = matching(rest, open: open, opener: "[", closer: "]")
    else { return [] }
    return literals(in: String(rest[(open + 1)..<close]))
      .filter { $0.label != "package:" }
      .map(\.value)
  }

  /// The string literals of `text`, each with the argument label just before it, if any.
  private static func literals(in text: String) -> [(label: String?, value: String)] {
    let parts = text.split(separator: "\"", omittingEmptySubsequences: false)
    return stride(from: 1, to: parts.count - 1, by: 2).map { index in
      let before = parts[index - 1].trimmingCharacters(in: .whitespaces)
      let label = before.split(separator: " ").last.map(String.init)
      return (label?.hasSuffix(":") == true ? label : nil, String(parts[index]))
    }
  }
}
