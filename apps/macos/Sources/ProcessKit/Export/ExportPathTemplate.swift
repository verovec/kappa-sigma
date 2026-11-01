package import Foundation

/// Where an export goes under its base folder (card 0151): a template such as
/// `{object}/{stack}/{date}-{time}`, each `/` a folder, each token a value of this export.
///
/// The values are made safe for one path component (a `/` or `:` in an object name becomes
/// `-`); a template that names an unknown token, or whose path would leave the base (`..`, `.`,
/// an absolute path), is refused with what to change. The folder shown is the folder written
/// (R2): the caller resolves it once and both shows and writes that URL.
package struct ExportPathTemplate: Equatable, Sendable {
  /// The default: one folder per object, per stack, per export (to the second).
  package static let standard = "{object}/{stack}/{date}-{time}"
  /// The tokens a template may use, in the order Settings lists them.
  package static let tokens = ["object", "stack", "date", "time", "project"]
  /// The tokens as the user types them: `{object}, {stack}, …`.
  package static var listed: String { tokens.map { "{\($0)}" }.joined(separator: ", ") }

  /// Why a template cannot name a folder under the base.
  package enum Refusal: Error, Equatable, Sendable {
    /// `{token}` is not one of `valid`.
    case unknownToken(String, valid: [String])
    /// The template (as typed) would leave the base: `..`, `.`, or an absolute path.
    case leavesBase(String)
    /// The template (as typed) has a `{` without its `}`, or a `}` without its `{`.
    case unbalancedBrace(String)
  }

  /// What the tokens stand for in one export.
  package struct Values: Equatable, Sendable {
    /// The stack's object, else the project's name.
    package var object: String
    /// The stack's bundle folder name.
    package var stack: String
    /// The project's name (its package without `.astrostack`).
    package var project: String
    /// When the export is made: `{date}` `yyyy-MM-dd`, `{time}` `HHmmss`.
    package var date: Date
    /// The zone the date and time are written in: the user's.
    package var zone: TimeZone

    /// The values of one export; an empty `object` (a stack of every light) is the project's.
    package init(object: String, stack: String, project: String, date: Date, zone: TimeZone) {
      self.object = object.isEmpty ? project : object
      self.stack = stack
      self.project = project
      self.date = date
      self.zone = zone
    }

    /// Values to check a template with when no export is at hand (Settings).
    package static let example = Self(
      object: "M 31", stack: "stack", project: "M31", date: Date(timeIntervalSince1970: 0),
      zone: .gmt)

    /// The value of `token`, or `nil` for a token that is not one.
    func value(of token: String) -> String? {
      let hour = Date.FormatStyle.Symbol.VerbatimHour.twoDigits(
        clock: .twentyFourHour, hourCycle: .zeroBased)
      let format: Date.FormatString
      switch token {
      case "object": return object
      case "stack": return stack
      case "project": return project
      case "date": format = "\(year: .padded(4))-\(month: .twoDigits)-\(day: .twoDigits)"
      case "time": format = "\(hour: hour)\(minute: .twoDigits)\(second: .twoDigits)"
      default: return nil
      }
      return date.formatted(
        Date.VerbatimFormatStyle(
          format: format, timeZone: zone, calendar: Calendar(identifier: .gregorian)))
    }
  }

  /// The template as typed.
  package let text: String

  /// The template `text`.
  package init(_ text: String) {
    self.text = text
  }

  /// The folder of an export with `values` under `base`; `base` itself for an empty template.
  package func folder(under base: URL, _ values: Values) throws(Refusal) -> URL {
    try components(values).reduce(base) { $0.appendingPathComponent($1, isDirectory: true) }
  }

  /// Why the template cannot name a folder for `values`, or `nil`.
  package func refusal(_ values: Values) -> Refusal? {
    do {
      _ = try components(values)
      return nil
    } catch {
      return error
    }
  }

  /// The folder names under the base, tokens replaced; empty names (`a//b`, a trailing `/`) are
  /// skipped.
  func components(_ values: Values) throws(Refusal) -> [String] {
    guard !text.hasPrefix("/") else { throw .leavesBase(text) }
    guard Self.balanced(text) else { throw .unbalancedBrace(text) }
    var names: [String] = []
    for part in text.split(separator: "/", omittingEmptySubsequences: true) {
      let name = try Self.substitute(String(part), values)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard name != ".", name != ".." else { throw .leavesBase(text) }
      if !name.isEmpty { names.append(name) }
    }
    return names
  }

  /// `part` with each `{token}` replaced by its value, made safe for a path component; text
  /// outside braces is kept as typed.
  private static func substitute(_ part: String, _ values: Values) throws(Refusal) -> String {
    var result = ""
    var rest = Substring(part)
    while let open = rest.firstIndex(of: "{"),
      let close = rest[open...].firstIndex(of: "}")
    {
      result += rest[..<open]
      let token = String(rest[rest.index(after: open)..<close])
      guard let value = values.value(of: token) else {
        throw .unknownToken(token, valid: tokens)
      }
      result += sanitised(value)
      rest = rest[rest.index(after: close)...]
    }
    return result + rest
  }

  /// Whether every `{` closes with a `}` before the next `{`, and no `}` is alone.
  private static func balanced(_ text: String) -> Bool {
    var open = false
    for character in text where character == "{" || character == "}" {
      guard open == (character == "}") else { return false }
      open.toggle()
    }
    return !open
  }

  /// `value` as one path component: `/` and `:` (the Finder's `/`) become `-`.
  package static func sanitised(_ value: String) -> String {
    String(value.map { $0 == "/" || $0 == ":" ? "-" : $0 })
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
