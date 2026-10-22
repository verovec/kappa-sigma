/// One line of a host tool's output, with the percentage it carries: what a run forwards to the
/// journal (`SirilLine` is the Siril-specific reading; GraXpert and the background engines use this).
package struct ToolProgress: Equatable, Sendable {
  /// The line as printed.
  package let line: String
  /// Its `N%`, when it has one at most 100 (`ProgressPercent`).
  package let percent: Int?

  /// A line with its percentage.
  package init(line: String, percent: Int?) {
    self.line = line
    self.percent = percent
  }

  /// A raw output line, its percentage read.
  package init(parsing line: String) {
    self.init(line: line, percent: ProgressPercent.first(in: line))
  }
}
